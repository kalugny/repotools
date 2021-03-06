# Functions injected into devtools namespace
# 
# Author: Renaud Gaujoux
###############################################################################

.shim_registry <- new.env()

set_shim <- function(envir, FUN, name = NULL, quiet = FALSE){
  
  # process envir
  if( isString(envir) ){
    envir <- strsplit(envir, '::')[[1L]]
    name <- name %||% envir[2L]
    envir <- asNamespace(envir[1L])
  }
  if( is.null(name) || !nzchar(name) ) stop("Invalid target function name (empty)")
  
  ename <- packageName(envir)
  # force function's environment
  fpkg <- packageName(topenv(environment(FUN)))
  key <- paste0(ename, '::', name)
  
  # backup original definition if necessary
  if( is.null(.shim_registry[[key]]) ){
    .shim_registry[[key]] <- envir[[name]]
  }
  
  eFUN <- FUN
  environment(eFUN) <- environment(envir[[name]])
  
  # inject if necessary
  if( digest(eFUN) != digest(envir[[name]]) ){
    # check if environment is locked
    was_locked <- bindingIsLocked(name, envir)
    if( was_locked ) do.call("unlockBinding", list(name, envir))
    
    # override function if necessary
    if( !quiet ){
      msg <- sprintf("Patching %s::%s with definition in %s [%s <- %s]"
          , ename, name, fpkg, sha1(.shim_registry[[key]] %||% envir[[name]]), sha1(eFUN))
      message(msg)
    }
    
    assign(name, eFUN, envir = envir)
    
#    if( isS3method(name, envir = envir) ) namespaceExport(envir, name)
    
    # lock it again if necessary
    if( was_locked ) lockBinding(name, envir)
    return(invisible(TRUE))
    
  }
  
  # return FALSE if nothing was injected 
  invisible(FALSE)
  
}

set_shims <- function(ns = topenv(parent.frame()), quiet = NULL){
  
  # inject shims into their respective namespace
  shims <- ls(ns, pattern = "^shim_")
  shims <- sapply(shims, get, envir = ns, simplify = FALSE)
  shims <- shims[sapply(shims, is.function)]
  names(shims) <- gsub("^shim_", '', names(shims))
  names(shims) <- sub("_", '::', names(shims))
  
  # log patches
  if( is.null(quiet) ){
    pkg <- packageName(ns)
    quiet <- !isDevNamespace(pkg)
    if( quiet ){
      t <- lengths(split(shims, sub("([^:]+).*", "\\1", names(shims))))
      msg <- sprintf("Applying %s patches to %s", pkg, paste0(sprintf("%s[%i]", names(t), t), collapse = ", "))
      packageStartupMessage(msg)
    }
  }
  
  sapply(names(shims), function(x){
        f <- shims[[x]]
        set_shim(x, f, quiet = quiet)
      })
  
}

reset_shim <- function(envir, name = NULL){
  
  # process envir
  if( isString(envir) ){
    envir <- strsplit(envir, '::')[[1L]]
    name <- name %||% envir[2L]
    envir <- asNamespace(envir[1L])
  }
  if( is.null(name) || !nzchar(name) ) stop("Invalid target function name (empty)")
  
  ename <- packageName(envir)
  was_locked <- bindingIsLocked(name, envir)
  if( was_locked ) do.call("unlockBinding", list(name, envir))
  key <- paste0(ename, '::', name)
  message(sprintf("Restoring definition for function %s::%s [%s <- %s]"
          , ename, name, digest(envir[[name]]), digest(.shim_registry[[key]])))
  envir[[name]] <- .shim_registry[[key]]
  if( was_locked ) lockBinding(name, envir)
  
}

with_shim <- function(envir, FUN, expr, name = NULL){
  
  # restore shim on exit
  on.exit(reset_shim(envir, name))
  if( !set_shim(envir, name) ) on.exit()
  
}
