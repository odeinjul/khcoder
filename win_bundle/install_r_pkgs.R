# Installs the R packages KH Coder's plotting code loads into the bundled R library.
lib <- file.path(R.home(), "library")
.libPaths(lib)
options(repos = c(CRAN = "https://cloud.r-project.org"), Ncpus = 4)

pkgs <- c(
	"ggplot2", "wordcloud", "amap", "RColorBrewer", "gtable", "proxy", "gridExtra",
	"topicmodels", "ggsci", "ggdendro", "cowplot", "Cairo", "vegan", "scatterplot3d",
	"som", "smacof", "pheatmap", "networkD3", "igraph", "ggnetwork", "devEMF",
	"colorspace", "MASS", "cluster"
)

# No longer on CRAN; built from the CRAN archive (needs Rtools).
archived <- c(
	maptools       = "https://cloud.r-project.org/src/contrib/Archive/maptools/maptools_1.1-8.tar.gz",
	RSVGTipsDevice = "https://cloud.r-project.org/src/contrib/Archive/RSVGTipsDevice/RSVGTipsDevice_1.0-7.tar.gz",
	ldatuning      = "https://cloud.r-project.org/src/contrib/Archive/ldatuning/ldatuning_1.0.2.tar.gz"
)

dep_fields <- c("Depends", "Imports", "LinkingTo")
base_pkgs <- rownames(installed.packages(priority = "base"))

missing_of <- function(p) setdiff(p, c(base_pkgs, rownames(installed.packages(lib))))

install.packages(missing_of(pkgs), lib = lib, type = "binary", dependencies = dep_fields)

# The archived packages still use Calloc/Free, which R >= 4.5 no longer defines.
makevars <- file.path(tempdir(), "Makevars.win")
writeLines("CPPFLAGS += -DCalloc=R_Calloc -DFree=R_Free -DRealloc=R_Realloc", makevars)
Sys.setenv(R_MAKEVARS_USER = makevars)

for (name in names(archived)) {
	tarball <- file.path(tempdir(), basename(archived[[name]]))
	download.file(archived[[name]], tarball, mode = "wb")
	untar(tarball, files = file.path(name, "DESCRIPTION"), exdir = tempdir())
	desc <- read.dcf(file.path(tempdir(), name, "DESCRIPTION"))
	deps <- unlist(lapply(intersect(dep_fields, colnames(desc)), function(f) strsplit(desc[, f], ",")[[1]]))
	deps <- trimws(sub("\\(.*", "", deps))
	deps <- setdiff(deps[nzchar(deps)], "R")
	need <- missing_of(deps)
	if (length(need)) install.packages(need, lib = lib, type = "binary", dependencies = dep_fields)
	install.packages(tarball, lib = lib, repos = NULL, type = "source")
}

still_missing <- missing_of(c(pkgs, names(archived)))
if (length(still_missing)) stop("R packages missing: ", paste(still_missing, collapse = ", "))

# Every package must actually load.
for (p in c(pkgs, names(archived))) {
	ok <- suppressPackageStartupMessages(requireNamespace(p, lib.loc = lib, quietly = TRUE))
	if (!ok) stop("R package fails to load: ", p)
}
cat("R packages OK:", length(rownames(installed.packages(lib))), "installed\n")
