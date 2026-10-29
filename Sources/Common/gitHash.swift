import BuildInfo

public let gitHash: String = unsafe String(cString: aerospaceGitHash)
public let gitShortHash: String = unsafe String(cString: aerospaceGitShortHash)
