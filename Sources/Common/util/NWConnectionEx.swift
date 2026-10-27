import Network
import Foundation
import Synchronization

extension NWConnection {
    public func writeAtomic(_ msg: some Encodable, _ encoder: JSONEncoder = JSONEncoder()) async -> ((), error: NWError?) {
        let payload = Result { try encoder.encode(msg) }.getOrDie()
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

    private func read(bytes size: Int) async -> Result<Data, NWError> {
        var data = Data(capacity: size)
        while data.count < size {
            let remaining = size - data.count
            let chunk: Result<Data, NWError> = await withCheckedContinuation { cont in
                receive(minimumIncompleteLength: remaining, maximumLength: remaining) { data, context, isComplete, error in
                    cont.resume(returning: error.map(Result.failure) ?? Result.success(data ?? Data()))
                }
            }
            switch chunk {
                case .success(let chunk): data.append(chunk)
                case .failure: return chunk
            }
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

    private func readUInt32() async -> Result<UInt32, NWError> {
        await read(bytes: 4).map { data in
            unsafe data.withUnsafeBytes { pointer in unsafe pointer.loadUnaligned(as: UInt32.self) }
        }
    }

    public func readNonAtomic() async -> Result<Data, NWError> {
        switch await readUInt32() {
            case .success(let count):
                return await read(bytes: Int(count))
            case .failure(let e):
                return .failure(e)
        }
    }

    /// The server's read of a request frame. nil for a client from before the frames: it starts with
    /// its protocol version, 1, instead of a frame length, and waits for the server's version. A request is never 1 byte
    /// long. Any other version makes the old client report that the client and the server are incompatible, rather than
    /// both waiting for each other
    public func readRequestFrame() async -> Result<Data, NWError>? {
        switch await readUInt32() {
            case .success(1):
                let version = withUnsafeBytes(of: UInt32(2)) { pointer in unsafe Data(pointer) }
                await withCheckedContinuation { cont in send(content: version, completion: .contentProcessed { _ in cont.resume() }) }
                return nil
            case .success(let count):
                return await read(bytes: Int(count))
            case .failure(let e):
                return .failure(e)
        }
    }
}
