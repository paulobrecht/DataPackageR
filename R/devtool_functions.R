# From devtools, unexported functions.
write_dcf <- function(path, desc) {
  desc <- unlist(desc)
  # Add back in continuation characters
  desc <- gsub("\n[ \t]*\n", "\n .\n ", desc, perl = TRUE, useBytes = TRUE)
  desc <- gsub("\n \\.([^\n])", "\n  .\\1", desc, perl = TRUE, useBytes = TRUE)
  
  starts_with_whitespace <- grepl("^\\s", desc, perl = TRUE, useBytes = TRUE)
  delimiters <- ifelse(starts_with_whitespace, ":", ": ")
  text <- paste0(names(desc), delimiters, desc, collapse = "\n")
  
  # If the description file has a declared encoding, set it so nchar() works
  # properly.
  if ("Encoding" %in% names(desc)) {
    Encoding(text) <- desc[["Encoding"]]
  }
  
  if (substr(text, nchar(text), 1) != "\n") {
    text <- paste0(text, "\n")
  }
  
  cat(text, file = path)
}
add_desc_package = function (pkg = ".", field, name) 
{
  pkg <- as.package(pkg)
  desc_path <- file.path(pkg$path, "DESCRIPTION")
  desc <- read_dcf(desc_path)
  old <- desc[[field]]
  if (is.null(old)) {
    new <- name
    changed <- TRUE
  }
  else {
    if (!grepl(paste0("\\b", name, "\\b"), old)) {
      new <- paste0(old, ",\n    ", name)
      changed <- TRUE
    }
    else {
      changed <- FALSE
    }
  }
  if (changed) {
    desc[[field]] <- new
    write_dcf(desc_path, desc)
  }
  invisible(changed)
}
is_installed = function (pkg, version = 0) 
{
  installed_version <- tryCatch(utils::packageVersion(pkg), 
                                error = function(e) NA)
  !is.na(installed_version) && installed_version >= version
}
read_dcf = function (path) 
{
  fields <- colnames(base::read.dcf(path))
  as.list(read.dcf(path, keep.white = fields)[1, ])
}
suggests_dep  = function (pkg) 
{
  suggests <- read_dcf(system.file("DESCRIPTION", package = "devtools"))$Suggests
  deps <- parse_deps(suggests)
  found <- which(deps$name == pkg)[1L]
  if (!length(found)) {
    stop(sQuote(pkg), " is not in Suggests: for devtools!", 
         call. = FALSE)
  }
  deps[found, ]
}
check_dep_version = function (dep_name, dep_ver = NA, dep_compare = NA) 
{
  if (!requireNamespace(dep_name, quietly = TRUE)) {
    stop("Dependency package ", dep_name, " not available.")
  }
  if (xor(is.na(dep_ver), is.na(dep_compare))) {
    stop("dep_ver and dep_compare must be both NA or both non-NA")
  }
  else if (!is.na(dep_ver) && !is.na(dep_compare)) {
    compare <- match.fun(dep_compare)
    if (!compare(as.numeric_version(getNamespaceVersion(dep_name)), 
                 as.numeric_version(dep_ver))) {
      warning("Need ", dep_name, " ", dep_compare, " ", 
              dep_ver, " but loaded version is ", getNamespaceVersion(dep_name))
    }
  }
  return(TRUE)
}
is_dir = function (x) {
  file.info(x)$isdir
}
check_suggested = function (pkg, version = NULL, compare = NA) 
{
  if (is.null(version)) {
    if (!is.na(compare)) {
      stop("Cannot set ", sQuote(compare), " without setting ", 
           sQuote(version), call. = FALSE)
    }
    dep <- suggests_dep(pkg)
    version <- dep$version
    compare <- dep$compare
  }
  if (!is_installed(pkg) || !check_dep_version(pkg, version, 
                                               compare)) {
    msg <- paste0(sQuote(pkg), if (is.na(version)) 
      ""
      else paste0(" >= ", version), " must be installed for this functionality.")
    if (interactive()) {
      message(msg, "\\nWould you like to install it?")
      if (menu(c("Yes", "No")) == 1) {
        install.packages(pkg)
      }
      else {
        stop(msg, call. = FALSE)
      }
    }
    else {
      stop(msg, call. = FALSE)
    }
  }
}
use_directory = function (path, ignore = FALSE, pkg = ".") 
{
  pkg <- as.package(pkg)
  pkg_path <- file.path(pkg$path, path)
  if (file.exists(pkg_path)) {
    if (!is_dir(pkg_path)) {
      stop("`", path, "` exists but is not a directory.", 
           call. = FALSE)
    }
  }
  else {
    message("* Creating `", path, "`.")
    dir.create(pkg_path, showWarnings = FALSE, recursive = TRUE)
  }
  if (ignore) {
    message("* Adding `", path, "` to `.Rbuildignore`.")
    use_build_ignore(path, pkg = pkg)
  }
  invisible(TRUE)
}

suggets_dep = function (pkg) 
{
  suggests <- read_dcf(system.file("DESCRIPTION", package = "devtools"))$Suggests
  deps <- parse_deps(suggests)
  found <- which(deps$name == pkg)[1L]
  if (!length(found)) {
    stop(sQuote(pkg), " is not in Suggests: for devtools!", 
         call. = FALSE)
  }
  deps[found, ]
}

use_git_ignore = function (ignores, directory = ".", pkg = ".", quiet = FALSE) 
{
  pkg <- as.package(pkg)
  paths <- paste0("`", ignores, "`", collapse = ", ")
  if (!quiet) {
    message("* Adding ", paths, " to ", file.path(directory, 
                                                  ".gitignore"))
  }
  path <- file.path(pkg$path, directory, ".gitignore")
  union_write(path, ignores)
  invisible(TRUE)
}

union_write = function (path, new_lines) 
{
  if (file.exists(path)) {
    lines <- readLines(path, warn = FALSE)
  }
  else {
    lines <- character()
  }
  all <- union(lines, new_lines)
  writeLines(all, path)
}

as.package = function (x = NULL, create = NA) 
{
  if (is.package(x)) 
    return(x)
  x <- package_file(path = x)
  load_pkg_description(x, create = create)
}

is.package = function (x) {
  inherits(x, "package")
}

package_file = function (..., path = ".") 
{
  if (!is.character(path) || length(path) != 1) {
    stop("`path` must be a string.", call. = FALSE)
  }
  path <- strip_slashes(normalizePath(path, mustWork = FALSE))
  if (!file.exists(path)) {
    stop("Can't find '", path, "'.", call. = FALSE)
  }
  if (!file.info(path)$isdir) {
    stop("'", path, "' is not a directory.", call. = FALSE)
  }
  while (!has_description(path)) {
    path <- dirname(path)
    if (is_root(path)) {
      stop("Could not find package root.", call. = FALSE)
    }
  }
  file.path(path, ...)
}

has_description = function (path) 
{
  file.exists(file.path(path, "DESCRIPTION"))
}

strip_slashes = function (x) 
{
  x <- sub("/*$", "", x)
  x
}

load_pkg_description = function (path, create) 
{
  path_desc <- file.path(path, "DESCRIPTION")
  if (!file.exists(path_desc)) {
    if (is.na(create)) {
      if (interactive()) {
        message("No package infrastructure found in ", 
                path, ". Create it?")
        create <- (menu(c("Yes", "No")) == 1)
      }
      else {
        create <- FALSE
      }
    }
    if (create) {
      setup(path = path)
    }
    else {
      stop("No description at ", path_desc, call. = FALSE)
    }
  }
  desc <- as.list(read.dcf(path_desc)[1, ])
  names(desc) <- tolower(names(desc))
  desc$path <- path
  structure(desc, class = "package")
}