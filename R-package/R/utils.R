#' @importClassesFrom Matrix dgCMatrix dgeMatrix
#' @import methods

# depends on matrix
.onLoad <- function(libname, pkgname) {
  library.dynam("xgboost", pkgname, libname)
}
.onUnload <- function(libpath) {
  library.dynam.unload("xgboost", libpath)
}

# set information into dmatrix, this mutate dmatrix
xgb.setinfo <- function(dmat, name, info) {
  if (class(dmat) != "xgb.DMatrix") {
    stop("xgb.setinfo: first argument dtrain must be xgb.DMatrix")
  }
  if (name == "label") {
    if (length(info)!=xgb.numrow(dmat))
      stop("The length of labels must equal to the number of rows in the input data")
    .Call("XGDMatrixSetInfo_R", dmat, name, as.numeric(info), 
          PACKAGE = "xgboost")
    return(TRUE)
  }
  if (name == "weight") {
    if (length(info)!=xgb.numrow(dmat))
      stop("The length of weights must equal to the number of rows in the input data")
    .Call("XGDMatrixSetInfo_R", dmat, name, as.numeric(info), 
          PACKAGE = "xgboost")
    return(TRUE)
  }
  if (name == "base_margin") {
    # if (length(info)!=xgb.numrow(dmat))
    #   stop("The length of base margin must equal to the number of rows in the input data")
    .Call("XGDMatrixSetInfo_R", dmat, name, as.numeric(info), 
          PACKAGE = "xgboost")
    return(TRUE)
  }
  if (name == "group") {
    if (length(info)!=xgb.numrow(dmat))
      stop("The length of groups must equal to the number of rows in the input data")
    .Call("XGDMatrixSetInfo_R", dmat, name, as.integer(info), 
          PACKAGE = "xgboost")
    return(TRUE)
  }
  stop(paste("xgb.setinfo: unknown info name", name))
  return(FALSE)
}

# construct a Booster from cachelist
xgb.Booster <- function(params = list(), cachelist = list(), modelfile = NULL) {
  if (typeof(cachelist) != "list") {
    stop("xgb.Booster: only accepts list of DMatrix as cachelist")
  }
  for (dm in cachelist) {
    if (class(dm) != "xgb.DMatrix") {
      stop("xgb.Booster: only accepts list of DMatrix as cachelist")
    }
  }
  handle <- .Call("XGBoosterCreate_R", cachelist, PACKAGE = "xgboost")
  if (length(params) != 0) {
    for (i in 1:length(params)) {
      p <- params[i]
      .Call("XGBoosterSetParam_R", handle, gsub("\\.", "_", names(p)), as.character(p),
            PACKAGE = "xgboost")
    }
  }
  if (!is.null(modelfile)) {
    if (typeof(modelfile) == "character") {
      .Call("XGBoosterLoadModel_R", handle, modelfile, PACKAGE = "xgboost")
    } else if (typeof(modelfile) == "raw") {
      .Call("XGBoosterLoadModelFromRaw_R", handle, modelfile, PACKAGE = "xgboost")      
    } else {
      stop("xgb.Booster: modelfile must be character or raw vector")
    }
  }
  return(structure(handle, class = "xgb.Booster.handle"))
}

# convert xgb.Booster.handle to xgb.Booster
xgb.handleToBooster <- function(handle, raw = NULL)
{
  bst <- list(handle = handle, raw = raw)
  class(bst) <- "xgb.Booster"
  return(bst)
}

# Check whether an xgb.Booster object is complete
xgb.Booster.check <- function(bst, saveraw = TRUE)
{
  isnull <- is.null(bst$handle)
  if (!isnull) {
    isnull <- .Call("XGCheckNullPtr_R", bst$handle, PACKAGE="xgboost")
  }
  if (isnull) {
    bst$handle <- xgb.Booster(modelfile = bst$raw)
  } else {
    if (is.null(bst$raw) && saveraw)
      bst$raw <- xgb.save.raw(bst$handle)
  }
  return(bst)
}

## ----the following are low level iteratively function, not needed if
## you do not want to use them ---------------------------------------
# get dmatrix from data, label
xgb.get.DMatrix <- function(data, label = NULL, missing = NULL) {
  inClass <- class(data)
  if (inClass == "dgCMatrix" || inClass == "matrix") {
    if (is.null(label)) {
      stop("xgboost: need label when data is a matrix")
    }
    if (is.null(missing)){
      dtrain <- xgb.DMatrix(data, label = label)
    } else {
      dtrain <- xgb.DMatrix(data, label = label, missing = missing)
    }
  } else {
    if (!is.null(label)) {
      warning("xgboost: label will be ignored.")
    }
    if (inClass == "character") {
      dtrain <- xgb.DMatrix(data)
    } else if (inClass == "xgb.DMatrix") {
      dtrain <- data
    } else {
      stop("xgboost: Invalid input of data")
    }
  }
  return (dtrain)
}
xgb.numrow <- function(dmat) {
  nrow <- .Call("XGDMatrixNumRow_R", dmat, PACKAGE="xgboost")
  return(nrow)
}
# iteratively update booster with customized statistics
xgb.iter.boost <- function(booster, dtrain, gpair) {
  if (class(booster) != "xgb.Booster.handle") {
    stop("xgb.iter.update: first argument must be type xgb.Booster.handle")
  }
  if (class(dtrain) != "xgb.DMatrix") {
    stop("xgb.iter.update: second argument must be type xgb.DMatrix")
  }
  .Call("XGBoosterBoostOneIter_R", booster, dtrain, gpair$grad, gpair$hess, 
        PACKAGE = "xgboost")
  return(TRUE)
}

# iteratively update booster with dtrain
xgb.iter.update <- function(booster, dtrain, iter, obj = NULL) {
  if (class(booster) != "xgb.Booster.handle") {
    stop("xgb.iter.update: first argument must be type xgb.Booster.handle")
  }
  if (class(dtrain) != "xgb.DMatrix") {
    stop("xgb.iter.update: second argument must be type xgb.DMatrix")
  }

  if (is.null(obj)) {
    .Call("XGBoosterUpdateOneIter_R", booster, as.integer(iter), dtrain, 
          PACKAGE = "xgboost")
  } else {
    pred <- predict(booster, dtrain)
    gpair <- obj(pred, dtrain)
    succ <- xgb.iter.boost(booster, dtrain, gpair)
  }
  return(TRUE)
}

# iteratively evaluate one iteration
xgb.iter.eval <- function(booster, watchlist, iter, feval = NULL, prediction = FALSE) {
  if (class(booster) != "xgb.Booster.handle") {
    stop("xgb.eval: first argument must be type xgb.Booster")
  }
  if (typeof(watchlist) != "list") {
    stop("xgb.eval: only accepts list of DMatrix as watchlist")
  }
  for (w in watchlist) {
    if (class(w) != "xgb.DMatrix") {
      stop("xgb.eval: watch list can only contain xgb.DMatrix")
    }
  }
  if (length(watchlist) != 0) {
    if (is.null(feval)) {
      evnames <- list()
      for (i in 1:length(watchlist)) {
        w <- watchlist[i]
        if (length(names(w)) == 0) {
          stop("xgb.eval: name tag must be presented for every elements in watchlist")
        }
        evnames <- append(evnames, names(w))
      }
      msg <- .Call("XGBoosterEvalOneIter_R", booster, as.integer(iter), watchlist, 
                   evnames, PACKAGE = "xgboost")
    } else {
      msg <- paste("[", iter, "]", sep="")
      for (j in 1:length(watchlist)) {
        w <- watchlist[j]
        if (length(names(w)) == 0) {
          stop("xgb.eval: name tag must be presented for every elements in watchlist")
        }
        preds <- predict(booster, w[[1]])
        ret <- feval(preds, w[[1]])
        msg <- paste(msg, "\t", names(w), "-", ret$metric, ":", ret$value, sep="")
      }
    }
  } else {
    msg <- ""
  }
  if (prediction){
    preds <- predict(booster,watchlist[[2]])
    return(list(msg,preds))
  }
  return(msg)
}
#------------------------------------------
# helper functions for cross validation
#
xgb.cv.mknfold <- function(dall, nfold, param) {
  if (nfold <= 1) {
    stop("nfold must be bigger than 1")
  }
  randidx <- sample(1 : xgb.numrow(dall))
  kstep <- length(randidx) %/% nfold
  idset <- list()
  for (i in 1:(nfold-1)) {
    idset[[i]] = randidx[1:kstep]
    randidx = setdiff(randidx,idset[[i]])
  }
  idset[[nfold]] = randidx
  ret <- list()
  for (k in 1:nfold) {
    dtest <- slice(dall, idset[[k]])
    didx = c()
    for (i in 1:nfold) {
      if (i != k) {
        didx <- append(didx, idset[[i]])
      }
    }
    dtrain <- slice(dall, didx)
    bst <- xgb.Booster(param, list(dtrain, dtest))
    watchlist = list(train=dtrain, test=dtest)
    ret[[k]] <- list(dtrain=dtrain, booster=bst, watchlist=watchlist, index=idset[[k]])
  }
  return (ret)
}
xgb.cv.aggcv <- function(res, showsd = TRUE) {
  header <- res[[1]]
  ret <- header[1]
  for (i in 2:length(header)) {
    kv <- strsplit(header[i], ":")[[1]]
    ret <- paste(ret, "\t", kv[1], ":", sep="")
    stats <- c()
    stats[1] <- as.numeric(kv[2])    
    for (j in 2:length(res)) {
      tkv <- strsplit(res[[j]][i], ":")[[1]]
      stats[j] <- as.numeric(tkv[2])
    }
    ret <- paste(ret, sprintf("%f", mean(stats)), sep="")
    if (showsd) {
      ret <- paste(ret, sprintf("+%f", sd(stats)), sep="")
    }
  }
  return (ret)
}
