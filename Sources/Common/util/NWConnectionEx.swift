import Network
import Foundation
import Synchronization

extension NWConnection {
    public func writeAtomic(_ msg: some Encodable, _ encoder: JSONEncoder = JSONEncoder()) async -> ((), error: NWError?) {
        await writeFrame(Result { try encoder.encode(msg) }.getOrDie())
    }

    public func writeFrame(_ payload: Data) async -> ((), error: NWError?) {
        var data = withUnsafeBytes(of: UInt32(payload.count)) { pointer in unsafe Data.init(pointer) }
        check(data.count == 4)
        data.append(payload)
        return await withCheckedContinuation { cont in
            send(content: data, completion: .contentProcessed { error in
                cont.resume(returning: ((), error))
            })
        }
    }

    public func initConnection() async -> ((), error: NWError?) {
        await withCheckedContinuation { cont in
            let isDone = Mutex(false)
            stateUpdateHandler = { state in
                let error: NWError?
                switch state {
                    case .preparing, .setup: return
                    case .ready: error = nil
                    case .failed(let e), .waiting(let e): error = e
                    case .cancelled: error = .posix(.ECANCELED)
                    @unknown default: die("Unknown NWConnection.State: \(state)")
                }
                // Make sure to resume continuation only once
                let wasAlreadyDone = isDone.withLock { isDone in
                    defer { isDone = true }
                    return isDone
                }
                if wasAlreadyDone { return }
                self.stateUpdateHandler = nil
                cont.resume(returning: ((), error))
            }
            start(queue: .global())
        }
    }

    private func read(bytes size: Int) async -> Result<Data, FrameReadError> {
        var data = Data()
        while data.count < size {
            let remaining = size - data.count
            let (chunk, isComplete, error): (Data?, Bool, NWError?) = await withCheckedContinuation { cont in
                receive(minimumIncompleteLength: remaining, maximumLength: remaining) { data, context, isComplete, error in
                    cont.resume(returning: (data, isComplete, error))
                }
            }
            if let error { return .failure(.network(error)) }
            if let chunk { data.append(chunk) }
            // Without this check, a read after the end of the stream would fail, or spin if it didn't (RB-08)
            if isComplete && data.count < size { return .failure(data.isEmpty ? .endOfStream : .closed) }
        }
        check(data.count == size)
        return .success(data)
    }

    public func readTillError() async {
        while true {
            let isError = await withCheckedContinuation { cont in
                receive(minimumIncompleteLength: 1, maximumLength: Int.max) { data, context, isComplete, error in
                    cont.resume(returning: error != nil || data == nil || data?.count == 0)
                }
            }
            if isError { return }
        }
    }

    private func readUInt32() async -> Result<UInt32, FrameReadError> {
        await read(bytes: 4).map { data in
            unsafe data.withUnsafeBytes { pointer in unsafe pointer.loadUnaligned(as: UInt32.self) }
        }
    }

    /// Reads one frame. A frame longer than `maxSize` isn't read
    public func readFrame(maxSize: UInt32 = .max) async -> Result<Data, FrameReadError> {
        switch await readUInt32() {
            case .success(1): .failure(.legacyProtocol)
            case .success(let size) where size > maxSize: .failure(.tooLarge(size: size, maxSize: maxSize))
            // The length was read, so the frame has begun
            case .success(let size): await read(bytes: Int(size)).mapError { e in if case .endOfStream = e { .closed } else { e } }
            case .failure(let e): .failure(e)
        }
    }

    /// The server's answer to a client from before the frames (FrameReadError.legacyProtocol): protocol version 2. Any
    /// version but its own makes the old client report that the client and the server are incompatible, rather than both
    /// waiting for each other
    public func answerLegacyHandshake() async {
        let version = withUnsafeBytes(of: UInt32(2)) { pointer in unsafe Data(pointer) }
        await withCheckedContinuation { cont in send(content: version, completion: .contentProcessed { _ in cont.resume() }) }
    }
}

/// Why `readFrame` failed
public enum FrameReadError: Error, CustomStringConvertible {
    /// The peer closed the connection before the first byte of the frame: after its last message, or without any
    case endOfStream
    /// The peer closed the connection before the frame was complete
    case closed
    /// A frame of length 1, which a JSON frame never is: the peer speaks the protocol from before the frames. Its client
    /// starts with its protocol version, 1. Its server reads the length of a frame as a client's version, answers with
    /// its own, 1, and closes the connection
    case legacyProtocol
    case tooLarge(size: UInt32, maxSize: UInt32)
    case network(NWError)

    public var description: String {
        switch self {
            case .endOfStream: "The connection was closed"
            case .closed: "The connection was closed in the middle of a message"
            case .legacyProtocol: "The other side speaks the older protocol with a version handshake"
            case .tooLarge(let size, let maxSize): "The message is \(size) bytes long. The limit is \(maxSize) bytes"
            case .network(let e): "\(e)"
        }
    }
}
