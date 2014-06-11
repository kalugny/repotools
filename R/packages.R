# Project: repotools
# 
# Author: Renaud Gaujoux
# Created: Jun 3, 2014
###############################################################################


#' @import digest
package.hash <- function(x){
        if( length(d <- find.package(x, quiet = TRUE)) ){
                digest(md5sum(list.files(d, full.names = TRUE, recursive = TRUE)))
        }else as.character(NA)
}
package.hash <- Vectorize(package.hash)

# match lowest/latest compatible version
match_available <- function(deps, available, latest = FALSE){
    
    dep_name <- if( is.character(deps) ) deps else deps$name
    
    # limit to packages in dependencies
    ia <- which(available[, 'Package'] %in% dep_name)
    if( !length(ia) ) return( setNames(rep(NA, length(dep_name)), dep_name))
    
    available <- available[ia, , drop = FALSE]
    # reorder as requested
    ov <- orderVersion(available[, 'Version'], decreasing = latest)
    available <- available[ov, , drop = FALSE]
    
    # case of a package name
    if( is.character(deps) ){
        i <- match(deps, available[, 'Package'])
        
    }else{
    
        # check against version requirement
        i_available <- function(pkg, compare, version) {
            if ( !length(i <- which(available[, 'Package'] == pkg)) ) NA
            else if (is.na(compare)) unname(i[1L])
            else{
                compare <- match.fun(compare)
                pass <- which(compare(package_version(available[i, 'Version']), version))
                if( length(pass) ) unname(i[pass[1L]])
                else NA
            }
        }
        i <- unlist(Map(i_available, deps$name, deps$compare, deps$version))
    }
    
    # remap
    setNames(ia[ov[i]], dep_name)
}

# adapted from devtools::install_deps
#' @importFrom tools package.dependencies
list.dependencies <- function(pkg, available, all = NA, missing.only = FALSE, recursive = FALSE, reduce = TRUE, rm.base = TRUE) 
{
    
    # internal workhorse function that list direct dependencies
    .list_dep <- function(pkg, all, depth = 1L){
        
        # empty result
        c0 <- character(0)
        empty <- data.frame(parent = c0, name = c0, compare = c0, version = c0, depLevel = c0, depth = numeric(0), stringsAsFactors = FALSE)
        
        # early exit if no package passed
        if( !nargs() ) return(empty)
        
        ipkg <- match_available(pkg, available)
        pkg_spec <- available[ipkg[!is.na(ipkg)], , drop = FALSE]
        # early exit if no package is found
        if( !nrow(pkg_spec) ) return(empty)
        
        # extract dependencies of each type
        dtype <- c('Depends', 'Imports')
        if( all ) dtype <- c(dtype, 'Suggests')
        deps <- sapply(dtype, function(x){
            d <- package.dependencies(pkg_spec, check = FALSE, depLevel = x)
            d <- sapply(names(d), function(p){
                    d <- d[[p]]
                    if( is_NA(d) ) return()
                    colnames(d) <- c('name', 'compare', 'version')
                    d[, 'name'] <- str_trim(d[, 'name'])
                    cbind(parent = p, d, depLevel = x)
                }, simplify = FALSE)
            d <- do.call(rbind, d)
        }
        , simplify = FALSE)
        # stick together
        deps <- as.data.frame(do.call(rbind, deps), stringsAsFactors = FALSE)
        # add depth
        if( nrow(deps) ) deps$depth <- depth
        
        #deps <- deps[deps$name != 'R', ]
        # filter already installed packages
        if( missing.only ){
            needs_install <- function(pkg, compare, version) {
                if( pkg == 'R' ){
                    compare <- match.fun(compare)
                    !compare(Rversion(), version)
                }else if (length(find.package(pkg, quiet = TRUE)) == 0) TRUE
                else if (is.na(compare)) FALSE 
                else{
                    compare <- match.fun(compare)
                    !compare(packageVersion(pkg), version)
                }
            }
            needed <- as.logical(Map(needs_install, deps$name, deps$compare, deps$version))
            deps <- deps[needed, , drop = FALSE]
        }
        deps
    }
    
    pkg_list <- pkg
    deps <- .list_dep()
    depth <- 1L
    if( identical(all, '*') ){
        all_rec <- TRUE
        all <- TRUE 
    }else all_rec <- NA
    
    while(TRUE){
        
        # resolve direct dependencies
        n <- nrow(deps)
        deps <- rbind(deps, .list_dep(pkg_list, isTRUE(all), depth))
        all <- all_rec
        depth <- depth + 1L
        # remove duplicated (keep larger depth)
        deps <- deps[!duplicated(paste0(deps$name, deps$compare, deps$version), fromLast = TRUE), ]
        
        if( n == nrow(deps) ) break;
        # resolve indirect dependencies
        if( !recursive ) break;
        
        pkg_list <- setdiff(deps$name, deps$parent)
        if( !length(pkg_list) ) break;
    }
    
    # remove base/recommended packages
    if( rm.base ){
        base_pkgs <- c("utils", "methods", "base", 'splines', 'graphics', 'stats', 'grDevices', 'tools', 'compiler', 'datasets', 'tcltk', 'stats4', 'grid', 'parallel') 
#        recom <- c("boot", "class", "cluster", "codetools", "foreign", "KernSmooth"
#                    , "lattice", "MASS", "Matrix", "mgcv", "nlme", "nnet", "rpart", "spatial", "survival")
        deps <- deps[! deps$name %in% base_pkgs, , drop = FALSE]
    }
    
    # reduce: keep max version and associate with larger depth (to allow inferring correct installation order)
    if( reduce && nrow(deps) ){
        if( anyDuplicated(deps$name) ){
            i <- split(seq(nrow(deps)), deps$name)
            sapply(i, function(i){
                if( length(i) > 1L ){
                    deps[i, 'depth'] <<- max(deps$depth[i], na.rm = TRUE)
                }
            })
            dname <- unique(deps$name)
            deps <- deps[orderVersion(deps$version, decreasing = TRUE), ]
            deps <- deps[!duplicated(deps$name), ]
            deps <- deps[order(match(deps$name, dname)), ]
        }
    }
    
    
    # return deps
    deps
}

#as.package_available <- function(x, available){
#    p <- available[, 'Package']
#    if( !x %in% p ) return(NA)
#    x <- structure(as.list(available[p == x, , drop = FALSE][1L, ]), class = 'package')
#    names(x) <- tolower(names(x))
#    x
#}


#' List Package Dependencies
#' 
#' @param x path to package source directory or file.
#' @param all logical that indicates if all dependencies should be returned,
#' or only the required ones.
#' @param available a matrix of available packages (as returned by \code{\link{available.packages}}), 
#' from which the dependencies are retrieved.
#' This means that there must be a row for the package \code{x}.
#' @param missing.only logical that indicates if only non-installed dependencies should be included in the 
#' result
#' @param recursive logical that indicates if indirect dependencies should also be included. 
#' @param as.list logical that indicates if the result should be a list with one element
#' per type of dependency.
#' @param names.only logical that indicates if the result should only include the dependencies package names
#' @param rm.base logical that indicates if base packages -- that come installed with any R installation -- 
#' should be exlcuded from the result.
#'  
#' @export
#' 
packageDependencies <- function(x, all = FALSE, available = NULL, missing.only = FALSE, recursive = FALSE, as.list = FALSE, names.only = TRUE, rm.base = TRUE){
    
    if( is_NA(available) ){
        x <- as_package(x, extract = TRUE)
        names(x) <- capwords(names(x))
        x <- t(as.matrix(unlist(x)))
        rownames(x) <- x[, 'Package']
    }else{
        if( is.null(available) ) available <- available.pkgs()
        p <- available[, 'Package']
        inp <- p %in% x
        if( !any(inp) ) return()
        x <- available[inp, , drop = FALSE]
    }
    
    deps <- list.dependencies(x[, 'Package'], available, all = all, missing.only = missing.only, recursive = recursive, rm.base = rm.base)
    
    if( as.list ){
        
        ideps <- split(seq_along(deps$name), deps$depLevel)
        deps <- sapply(ideps, function(i){
                                    if( !names.only ) deps[i, , drop = FALSE]
                                    else unique(deps$name[i])
                            }, simplify = FALSE)
            
    }else if( names.only ) deps <- unique(deps$name)
    
    deps
    
    
}

# adapted from devtools::parse_deps
parse_deps <- function (string) 
{
	if (is.null(string)) 
		return()
	string <- gsub("\\s*\\(.*?\\)", "", string)
	pieces <- strsplit(string, ",")[[1]]
	pieces <- gsub("^\\s+|\\s+$", "", pieces)
	pieces[pieces != "R"]
}

pkg.dependencies <- function(pkg, dependencies = NA, ..., verbose = TRUE){
    install.pkgs(pkg, dependencies = dependencies, ..., dry.run = TRUE, verbose = verbose)
}

# utils to list dependencies
str_deps <- function(x, n = 5L){    
    v <- ifelse(is.na(x$compare), '', sprintf(" (%s %s)", x$compare, x$version))
    str_out(paste0(x$name, v), n, total = TRUE)
}


#' Installing All Package Dependencies
#' 
#' Install all dependencies from a package source directory or 
#' package source file. 
#' 
#' @param pkg package name, path or source file
#' @inheritParams install.pkgs
#' @param ... extra arguments passed to \code{\link{install.pkgs}}.
#' 
#' @export
#' @examples 
#' 
#' try( install.dependencies('Matrix', dry.run=TRUE) )
#' \dontrun{
#' install.dependencies("mypackage_1.0.tar.gz", dry.run=TRUE)
#' }
#' 
install.dependencies <- function(pkg, dependencies = NA, ..., verbose = TRUE, dry.run = FALSE) 
{
    # dump messages if requested
    if( !verbose ) message <- function(...) NULL
    
    # list dependencies
    deps <- pkg.dependencies(pkg, dependencies = dependencies, ..., verbose = FALSE)
    pkg_names <- deps$name[deps$depth == 0]
    deps <- deps[deps$depth > 0, , drop = FALSE]
    message("Package dependencies to install ", pkg_names, ": ", str_deps(deps, Inf))
	if( !dry.run ){
        message("Installing ", nrow(deps), " dependencies")
		install.pkgs(deps, ...)
	}
	invisible(deps)
}
