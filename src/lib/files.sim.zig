//
// The test input factories for the functions in `files.zig`, so Faultline can call them with every
// filesystem error a command can hit.
//

//
// What `skl install` hits when `skl.yaml` names a local working tree that does not exist.
//
pub fn missingFileError() anyerror {
    return error.FileNotFound;
}

//
// What `skl install` hits in a project whose `.claude` directory the user cannot write to.
//
pub fn accessDeniedError() anyerror {
    return error.AccessDenied;
}

//
// What `skl install` hits when the filesystem refuses an operation for lack of permission.
//
pub fn permissionDeniedError() anyerror {
    return error.PermissionDenied;
}

//
// What `skl init` hits when `skl.yaml` is a directory and not a file.
//
pub fn isDirectoryError() anyerror {
    return error.IsDir;
}

//
// What `skl install` hits when `.claude` is a file and not a directory.
//
pub fn notDirectoryError() anyerror {
    return error.NotDir;
}

//
// What `skl add acme/skills --ns <name>` hits when the namespace makes a path longer than the
// system allows.
//
pub fn nameTooLongError() anyerror {
    return error.NameTooLong;
}

//
// What `skl install` hits when a skill's link points back at itself.
//
pub fn symLinkLoopError() anyerror {
    return error.SymLinkLoop;
}

//
// What `skl list` hits when a package's README is larger than a file can be.
//
pub fn fileTooBigError() anyerror {
    return error.FileTooBig;
}

//
// What `skl list` hits when a package's README is larger than `skl` reads.
//
pub fn streamTooLongError() anyerror {
    return error.StreamTooLong;
}

//
// What `skl install` hits on a disk that is full.
//
pub fn noSpaceLeftError() anyerror {
    return error.NoSpaceLeft;
}

//
// What `skl install` hits when the system runs short of what a file operation needs.
//
pub fn systemResourcesError() anyerror {
    return error.SystemResources;
}

//
// What `skl install` hits when the process has used up its open files.
//
pub fn processFdQuotaExceededError() anyerror {
    return error.ProcessFdQuotaExceeded;
}

//
// What `skl install` hits when the system has used up its open files.
//
pub fn systemFdQuotaExceededError() anyerror {
    return error.SystemFdQuotaExceeded;
}

//
// What `skl list` hits when the system runs out of memory.
//
pub fn outOfMemoryError() anyerror {
    return error.OutOfMemory;
}

//
// What `skl install` hits when the filesystem reports an error `skl` has no words of its own for.
//
pub fn unexpectedError() anyerror {
    return error.Unexpected;
}

//
// The working tree in `skl add acme/skills --ns demo --local /home/skilled/local-skills`, written
// as an absolute path.
//
pub fn absoluteLocalPath() []const u8 {
    return "/home/skilled/local-skills";
}
