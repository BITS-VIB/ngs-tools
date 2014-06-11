#!/usr/bin/RScript

# get all gens in a given locus (hs or mm)
# if asked, compute GO enrichment (BP)
#
# usage: locus2genes.R -h
#
# Stephane Plaisance VIB-BITS June-10-2014 v1.0

script.version = "v1.0"

# required R-packages
# once only install.packages("optparse")
suppressPackageStartupMessages(library("optparse"))

#####################################
### Handle COMMAND LINE arguments ###
#####################################

# parameters
#  make_option(c("-h", "--help"), action="store_true", default=FALSE,
#              help="plots from logmyapp monitoring data")

option_list <- list(
  make_option(c("-r", "--region"), type="character", 
              help="genomic region(s)
              	- format: \'chr:from:to<:strand>\' eg: \"1:1:100000\"
              	- if multiple, comma-separated and no-space eg: \"1:1:100000,2:1000:15000\""),
  make_option(c("-o", "--organism"), type="character", default='hs' ,
            help="mouse=mm: (GRCm38.p2) or human=hs (GRCh37.p13) [default: %default]"),
  make_option(c("-e", "--enrichment"), type="character", default='no',
            help="compute MF/BP enrichment (yes/no) [default: %default]"),
  make_option(c("-c", "--ontology"), type="character", default='BP',
            help="Ontology class to be used for enrichment (BP/MF/CC) [default: %default]"),
  make_option(c("-n", "--minnodes"), type="integer", default=1, 
            help="keeping a GO term with minimum nodes of (5-10 for stringency) [default: %default]"),
  make_option(c("-b", "--background"), type="character", default='no',
            help="user provides a list of 'entrezID's as background, (yes/no) [default: %default]"),
  make_option(c("-f", "--backgroundfile"), type="character", default='',
            help="file with background 'entrezID' list for stats (one ID per line)"),
  make_option(c("-t", "--topresults"), type="integer", default=10, 
            help="return N top results from stat test [default: %default]")
  )

## parse options
opt <- parse_args(OptionParser(option_list=option_list))

# check if arguments were provided (or do nothing)
if ( length(opt) == 0 ) {
	stop("# you did not provide arguments, quitting!")
	}

## test valid choices
# test organism choice
if ( ! (opt$organism %in% c("hs", "mm") ) ) {
	stop("Invalid <value> for '-o' , use 'hs' for human (GRCh37.p13), and 'mm' for mouse (GRCm38.p2)!")
	}
	
# test ontology choice
if ( ! (opt$ontology %in% c("MF", "BP", "CC") ) ) {
	stop("Invalid <value> for '-g' , use 'MF', 'BP', or 'CC'!")
	}

########################################
## main code to retrieve genes from locus

# required to find genes from locus region
if("biomaRt" %in% rownames(installed.packages()) == FALSE) {
	stop("biomaRt does not seem to be installed!")
	}
suppressPackageStartupMessages(library("biomaRt"))

# use the 'ensembl' mart
ensembl = useMart("ensembl")

# connect database
if (opt$organism == "mm") {
	# we work with mouse data
	refgenome <- "mmusculus_gene_ensembl"
} else {
	# we work with human data
	refgenome <- "hsapiens_gene_ensembl"
}

cat("\n### Connecting to BiomaRt\n")	
ensembl = useDataset(refgenome, mart=ensembl)

# set filtering to region
sel.filters = "chromosomal_region"

# get region(s) from argument(s)
chrom.region <- unlist(strsplit(opt$region, split=","))

# remove 'chr' if present
chrom.region <- gsub("^chr", "", chrom.region, ignore.case = TRUE, perl = TRUE,
     fixed = FALSE, useBytes = FALSE)

# set attributes
sel.attributes = c("ensembl_gene_id",
				 "external_gene_id",
				 "entrezgene",
				 "chromosome_name",
				 "start_position",
				 "end_position",
				 "strand" )

cat("\n### Fetching genes in region(s)", "\n")
bm.results <- getBM(attributes = sel.attributes,
					filters = sel.filters,
					values = chrom.region,
					mart = ensembl)
					
# replace blank cells by NA
bm.results[bm.results == ""] <- NA

# sort by chr and position
bm.results <- bm.results[order(bm.results$chromosome_name, bm.results$start_position),]
cat("\n## BiomaRt Found:", nrow(bm.results), " genes in region(s)\n")

# list of entrezIDs
bm.results.entrezIDs <- subset(bm.results, ! is.na(bm.results$entrezgene) )$entrezgene
test.len <- length(bm.results.entrezIDs)
cat("\n## Of which:", test.len, " have entrezID(s)\n")

if (test.len == 0) {
		stop("cannot proceed without entrez IDs, try to increase your locus size!")
		}

# create name including query
locus.str <- paste(gsub(":", "-", chrom.region, ignore.case = FALSE, fixed = FALSE), collapse="_")

cat("\n### Saving results to files", "\n")
# save full table
outfile1 <- paste("all_genes_", locus.str, "_", opt$organism,".txt", sep="")

write.table(bm.results, 
			file = outfile1, 
			row.names = FALSE, 
			sep = "\t", 
			quote = FALSE, 
			dec = ",",
			na = "NA",
			col.names = TRUE)

# save entrezID list
outfile2 <- paste("entrezIDs_", locus.str, "_", opt$organism ,".txt", sep="")

write.table(bm.results.entrezIDs, 
			file=outfile2, 
			row.names = FALSE, 
			quote = FALSE, 
			col.names = FALSE)

#################################
## enrichment analysis (optional)

# if enrichment, check for required package
if (opt$enrichment == "yes") {

	# required to compute GO enrichment
	if ("topGO" %in% rownames(installed.packages()) == FALSE) {
		stop("biomaRt does not seem to be installed!")
		}
	cat("\n### Loading the topGO library\n")
	suppressPackageStartupMessages(library("topGO"))

	# choose reference organism for GO enrichment
	if (opt$organism == "hs") {
		# we work with human data
		refgenome <- "hsapiens_gene_ensembl"
		go.ref <- "org.Hs.eg.db"
	} else {
		# we work with mouse data
		refgenome <- "mmusculus_gene_ensembl"
		go.ref <- "org.Mm.eg.db"
	}
	
	# check if database is installed
	if(go.ref %in% rownames(installed.packages()) == FALSE) {
			stop(paste(go.ref, "does not seem to be installed!", sep=" "))
			}
	cat("\n### Connecting with", go.ref ,"\n")
	suppressPackageStartupMessages(library(go.ref, character.only = TRUE))

	## user provides a universe list of genes for background 
	if (opt$background == 'yes') {
		# check that infile exists
		if (file.access(opt$backgroundfile) == -1) {
		  stop(sprintf("Specified file ( %s ) does not exist", opt$backgroundfile))
		  }

		# load background data
		user.ref <- read.table(opt$backgroundfile, quote="\"")
		backgrnd.len = nrow(user.ref)
		backgrnd.name = paste("'", opt$backgroundfile, "'", sep="")
		cat(paste("The chosen background list contains ", backgrnd.len, " entrezIDs.\n"))
		bckgrn.lab = "user-data"
		universe = user.ref$V1
	} else {
		# get all geneIDs for stats below, store in factor
		cat("\n### Fetching full-genome list of genes for background set", "\n")
		all.entrezgene <- getBM(attributes = "entrezgene",
						values = "*", 
						mart = ensembl)$entrezgene
		backgrnd.len = length(all.entrezgene)
		backgrnd.name = paste("'all'", opt$organism, "genes", sep=" ")
		bckgrn.lab = "all"
		universe = all.entrezgene
	}

	# create a named list with the universe AND
	# flag the subset comming from the locus selection with '1'
	user.list <- bm.results.entrezIDs
	test.list <- factor(as.integer(universe %in% user.list))
	names(test.list) <- universe
	
	# test for presence of two levels or die
	if(length(levels(test.list)) != 2) {
			stop("One (or both) provided list does not allow GO enrichment!")
			}

	# prune GO with less than opt$minnodes
	cat("\n### Building GO object to compute enrichment in region(s)", "\n")
	GOdata <- new("topGOdata", 
				  ontology = opt$ontology, 
				  allGenes = test.list, 
				  geneSel = function(p) p < 0.01,
				  description = "Fisher enrichment test",
				  nodeSize = opt$minnodes,
				  annot = annFUN.org, 
				  mapping = go.ref, 
				  ID = "entrez")

	# compute enrichment with Fisher test
	cat("\n### Computing Fisher test", "\n")
	resultFisher <- runTest(GOdata, 
							algorithm = "classic", 
							statistic = "fisher")
							
	# store top results in table
	res.table <- GenTable(GOdata, 
								Fis = resultFisher, 
								orderBy = "Fis", 
								topNodes = opt$topresults)
	res.title <- "\n### Fisher test summary :"
	
	# save full table
	outfile3 <- paste(opt$ontology, "-enrichment_", "_min-", opt$minnodes, "_", 
		opt$organism, "-", locus.str, "_vs_", bckgrn.lab, ".txt", sep="")
	cat("\n### Saving enrichment results for region(s) to: ", outfile3, "\n")
	
	# prepare citation
	citation <- citation("topGO")
	
	# print the results to file
	sink(file=outfile3)
	cat(paste("#### locus2genes (©SP:BITS2014, ", script.version, "), ", 
				Sys.Date(), Sys.time(), sep=""))  
  	cat(paste("\n### GO-", opt$ontology, " enrichment results for locus: ", 
  				opt$region, " (", test.len, " entrezIDs)",
  	  			"\n## against:", backgrnd.name,	" (", backgrnd.len, " entrezIDs)", 
  	  			sep=""))
  	cat("\n## organism : ", refgenome)
  	cat(" ")
  	cat("\n\n### GOdata summary: ", "\n")
  	print(GOdata)

  	cat("\n## results for Fisher\n")
  	print(resultFisher)
  	
    cat("\n\n### Enrichment results", "\n")
  	cat(res.title, "\n")
  	cat(" \n")
  	print(res.table)
  	cat ("\n\n---------\n## REFERENCE:", "\n")
  	print(citation$textVersion)
  	sink()
}

cat("\n### Finished successfully!\n")