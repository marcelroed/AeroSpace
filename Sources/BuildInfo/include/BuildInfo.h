// The values live in buildInfoGenerated.c, which generate.sh rewrites for every release build.
// A new commit then recompiles only that C file and relinks, instead of every Swift module that imports Common
extern const char *const _Nonnull aerospaceGitHash;
extern const char *const _Nonnull aerospaceGitShortHash;
