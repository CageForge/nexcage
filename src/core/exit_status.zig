/// The status `exec` has to exit with.
///
/// An OCI runtime propagates the status of the command it ran: `runc exec web
/// false` exits 1, and a caller such as containerd or a readiness probe reads
/// that status rather than "the runtime succeeded". nexcage's other commands
/// use the documented scheme (0, 1, 2), so `exec` needs a way to say "exit
/// with this instead", and the command interface returns `Error!void`.
///
/// null when nothing set it, which is every command but `exec`.
pub var propagated: ?u8 = null;
