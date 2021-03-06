#!/usr/bin/env Rscript

# ------------------------------------------------------------------------------
# 
# Author: Gabriele Girelli
# Email: gigi.ga90@gmail.com
# Description: plot probes ideograms.
# 
# ------------------------------------------------------------------------------



# DEPENDENCIES =================================================================

suppressMessages(library(GGally))
suppressMessages(library(argparser))
suppressMessages(library(ggplot2))
suppressMessages(library(ggpubr))
suppressMessages(library(gridExtra))
suppressMessages(library(scales))
suppressMessages(library(viridis))

# INPUT ========================================================================

# Create arguent parser
scriptName = "plotIdeograms.R"
parser = arg_parser('Plot ideograms with probes location, per cell type.',
	name = scriptName)

# Define mandatory arguments
parser = add_argument(parser, arg = 'dotsTable', type = class(""),
	help = 'Path to dots table.')
parser = add_argument(parser, arg = 'probesBed', type = class(""),
	help = 'Path to probes bed file. No header, track line.')
parser = add_argument(parser, arg = 'giemsaBed', type = class(""),
	help = 'Path to giemsa bands bed file. No header, track line.')
parser = add_argument(parser, arg = 'outputFolder', type = class(""),
	help = 'Path to output folder.')

# Version argument
version_flag = "0.0.1"
parser = add_argument(parser, arg = '--version', short = '-V',
	help = 'Print version and quit.', flag = T)

args = commandArgs(trailingOnly=TRUE)
if ( "--version" %in% args ) {
	cat(sprintf("%s v%s\n", scriptName, version_flag))
	quit()
}

# Parse arguments
p = parse_args(parser)

# Attach argument values to variables
attach(p['' != names(p)], warn.conflicts = F)

if ( !file.exists(dotsTable) )
	stop(sprintf("dots table not found: %s\n", dotsTable))
if ( !file.exists(probesBed) )
	stop(sprintf("probes bed file not found: %s\n", probesBed))
if ( !file.exists(giemsaBed) )
	stop(sprintf("giemsa ands bed file not found: %s\n", giemsaBed))
if ( !file.exists(outputFolder) )
	cat(sprintf("Output folder not found, created: %s\n", outputFolder))
	dir.create(outputFolder, showWarnings = F)

initial.options <- commandArgs(trailingOnly = FALSE)
file.arg.name <- "--file="
script.name <- sub(file.arg.name, "",
    initial.options[grep(file.arg.name, initial.options)])
script.basename <- dirname(script.name)

# FUNCTIONS ====================================================================

source(file.path(script.basename, "common.functions.R"))

read_giemsa_for_ideogram = function(path, space_between_chrom = 5) {
    giemsa = read.delim(path, as.is = T, header = F, skip = 1)
    colnames(giemsa) = c("chrom", "start", "end", "name", "value")
    giemsa = add_chrom_ID(giemsa)
    giemsa$reg_uID = paste0(giemsa$chrom, '~', giemsa$start, '~', giemsa$end)
    giemsa$x = (giemsa$chromID-1)*(2+max(1, space_between_chrom))

    # Prepare table for non-centromeric polygons
    data = data.frame(
        chrom = rep(giemsa$chrom, each = 4),
        chromID = rep(giemsa$chromID, each = 4),
        y = c(t(cbind(giemsa$start, giemsa$start, giemsa$end, giemsa$end))),
        x = c(t(cbind(giemsa$x, giemsa$x+1, giemsa$x+1, giemsa$x))),
        value = rep(giemsa$value, each = 4),
        id = rep(giemsa$reg_uID, each = 4),
        stringsAsFactors = F
    )

    # Prepare centromeric table by merging centromeric regions per chromosome
    data = data[data$value != "acen",]
    acen = giemsa[giemsa$value == "acen",]
    acen = do.call(rbind, by(acen, acen$chrom, FUN = function(ct) {
        data.frame(
            chrom = ct$chrom[1],
            start = min(ct$start),
            end = max(ct$end),
            name = NA,
            value = "acen",
            chromID = ct$chromID[1],
            x = ct$x[1],
            reg_uID = ct$reg_uID[1],
            stringsAsFactors = F
        )
    }))

    # Add centromeric triangles
    data = rbind(data, data.frame(
        chrom = rep(acen$chrom, each = 4),
        chromID = rep(acen$chromID, each = 4),
        y = c(t(cbind(acen$start, acen$start, acen$end, acen$end))),
        x = c(t(cbind(acen$x, acen$x+1, acen$x, acen$x+1))),
        value = rep(acen$value, each = 4),
        id = rep(acen$reg_uID, each = 4),
        stringsAsFactors = F
    ))
    giemsa_palette = c(
        "#DDDDDD", "#9A9A9A", "#787878", "#555555", "#333333",
        "#FF0000", "#C4FFFC", "#AFE6FF")
    giemsa_levels = c(
        )
    data$value = factor(data$value, levels = giemsa_levels)
    names(giemsa_palette) = giemsa_levels

    return(data)
}

plot_ideogram_probes = function(probesBed, dotsTable,
    plot_title = NULL, giemsa_path = NA
    ) {
	cts = sort(unique(dotsTable$cell_type))
	space_between_chrom = length(cts) + 1

	# Prepare probe table
	probe_data = do.call(rbind, by(dotsTable, dotsTable$cell_type,
		FUN = function(ct) {
			ctProbes = probesBed
			ctProbes$cell_type = ct$cell_type[1]

			probes = unique(ct$probe_label)
			ctProbes$available = 0
			ctProbes$available[ctProbes$name %in% probes] = 1

			ctProbes$x = (ctProbes$chromID-1)*(2+max(1, space_between_chrom))
			ctProbes$x = ctProbes$x+which(cts == ct$cell_type[1])+1

			ctProbes$y = (ctProbes$start-ctProbes$end)/2 + ctProbes$start

			return(ctProbes)
		})
	)

	probe_labels = do.call(rbind, by(probe_data, probe_data$chrom,
		FUN = function(chromt) {
			do.call(rbind, lapply(1:length(cts), FUN = function(cti) {
				chromID = chromt$chromID[1]
		        data.frame(
		        	cell_type = cts[cti],
		            x = (chromID-1)*(2+max(1, space_between_chrom))+cti+1,
		            y = -5e6,
		            stringsAsFactors = F
		        )
			}))
	    })
	)

    # Giemsa datatrack
    if ( is.na(giemsa_path) )
        giemsa_path = "/media/Data/Resources/hg19.giemsa_bands.txt"
    data = read_giemsa_for_ideogram(giemsa_path,
        space_between_chrom = space_between_chrom)

    chrom_labels = do.call(rbind, by(data, data$chrom, FUN = function(ct) {
        data.frame(
            chrom = ct$chrom[1],
            chromID = ct$chromID[1],
            x = min(ct$x) + .5,
            y = -5e6,
            value = NA,
            id = NA,
            stringsAsFactors = F
        )
    }))

    giemsa_palette = c(
        "#DDDDDD", "#9A9A9A", "#787878", "#555555", "#333333",
        "#FF0000", "#C4FFFC", "#AFE6FF")
    names(giemsa_palette) = c(
        "gneg", "gpos25", "gpos50", "gpos75", "gpos100",
        "acen", "gvar", "stalk")

    # Plot
    p = ggplot(data, aes(x = x, y = -y)
        ) + geom_polygon(aes(fill = value, group = id)
        ) + geom_text(data = chrom_labels, aes(label = chrom),
        	size = 5, angle = 90, hjust = 0
        ) + scale_fill_manual(values = giemsa_palette
        ) + theme_bw() + theme(
            axis.ticks.x = element_blank(),
            axis.text.x = element_blank(),
            axis.title.x = element_blank(),
            axis.ticks.y = element_blank(),
            axis.text.y = element_blank(),
            axis.title.y = element_blank(),
            panel.grid = element_blank(),
            text = element_text(size = 20, family = "Helvetica")
        ) + guides(fill = guide_legend(title = "Giemsa")
        ) + geom_point(data = probe_data,
        	color = "#989898", size = 1.5, shape = 19
        ) + geom_point(data = probe_data[1 == probe_data$available,],
        	color = "#2443CC", size = 3, shape = 19
        ) + geom_text(data = probe_labels, aes(label = cell_type),
        	size = 5, angle = 90, hjust = 0
        )

    if ( class(NULL) != class(plot_title) ) {
        p = p + ggtitle(plot_title)
    }

    return(p)
}

# Author: FA
# Function to save the plot (and separately its data)
# to file and show the plot in the notebook
save_and_plot <- function(x, bname, width, height,
    dpi=300, use.cowplot=FALSE, ncol=1, nrow=1,
    base_height=4, base_width=NULL, base_aspect_ratio=1,
    plot=FALSE, formats = c("png", "eps", "pdf")){
  if( !use.cowplot ){
    if ( "png" %in% formats) {
        png(filename=file.path(paste0(bname, ".png")),
            units="in", height=height, width=width, res=dpi)
        print(x)
        while(length(dev.list())>0) invisible(dev.off())
    }
    if ( "pdf" %in% formats) {
        cairo_pdf(filename=file.path(paste0(bname, "_cairo_pdf.pdf")),
            onefile = TRUE, height=height, width=width, family="Helvetica",
            pointsize=8, antialias="none")
        print(x)
        while(length(dev.list())>0) invisible(dev.off())
    }
    if ( "eps" %in% formats) {
        cairo_ps(filename=file.path(paste0(bname, "_cairo_ps.eps")),
            onefile = TRUE, height=height, width=width, family="Helvetica",
            pointsize=8, antialias="none")
        print(x)
        while(length(dev.list())>0) invisible(dev.off())
        postscript(file=file.path(paste0(bname, "_postscript.eps")),
            onefile = TRUE, paper="special", height=height, width=width,
            family="Helvetica", pointsize=8, horizontal=FALSE)
        print(x)
        while(length(dev.list())>0) invisible(dev.off())
    }
  }else{
    if ( "png" %in% formats) {
        save_plot(x, filename=file.path(paste0(bname, ".png")),
            ncol = ncol, nrow = nrow, base_height = base_height,
            base_width = base_width, base_aspect_ratio = base_aspect_ratio,
            dpi=dpi)
        while(length(dev.list())>0) invisible(dev.off())
    }
    if ( "pdf" %in% formats) {
        save_plot(x, filename=file.path(paste0(bname, "_cairo_pdf.pdf")),
            ncol = ncol, nrow = nrow, base_height = base_height,
            base_width = base_width, base_aspect_ratio = base_aspect_ratio,
            device=cairo_pdf)
        while(length(dev.list())>0) invisible(dev.off())
    }
    if ( "eps" %in% formats) {
        save_plot(x, filename=file.path(paste0(bname, "_cairo_ps.eps")),
            ncol = ncol, nrow = nrow, base_height = base_height,
            base_width = base_width, base_aspect_ratio = base_aspect_ratio,
            device=cairo_ps)
        save_plot(x, filename=file.path(paste0(bname, "_postscript.eps")),
            ncol = ncol, nrow = nrow, base_height = base_height,
            base_width = base_width, base_aspect_ratio = base_aspect_ratio,
            device="ps")  
        while(length(dev.list())>0) invisible(dev.off())
    }
  }
  if( plot ) print(x)
}

# RUN ==========================================================================

bpro = read_probe_bed(probesBed)
tdot = read_dot_table(dotsTable)

p = plot_ideogram_probes(bpro, tdot, "test", giemsaBed)

save_and_plot(p, file.path(outputFolder,
    "probes.merged.noDiscardedChannels.G1selected"), width = 45, height = 20)

# END ==========================================================================

################################################################################