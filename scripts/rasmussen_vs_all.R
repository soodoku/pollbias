"

Rasmussen vs. the rest

"

# setwd
setwd(githubdir)
setwd("pollbias")

# read in the data
approve  <- read.csv("data/bushfav_merged.csv")
election <- read.csv("data/collapsed polls_pollster.csv")

# load libs 
library(ggplot2)
library(directlabels)

# Plot approval: R vs. Rest 
approve$rasmussen <- ifelse(approve$organization=="Rasmussen", "Rasmussen", "Other")

p <- 
ggplot(data=approve, aes(x=as.numeric(week), y=approve, col=rasmussen)) +
geom_point(alpha = .4, shape=16) +
geom_smooth() + 
scale_colour_manual(values = c("#999999", "#bb7777")) + 
scale_y_continuous("Percent Approving Bush") + 
scale_x_continuous("Week of the presidency") + 
theme_minimal() +
theme(panel.grid.major  = element_line(color="#e7e7e7",  linetype = "dotted"),
	  panel.grid.minor  =  element_blank(),
	  legend.position   = c(30,40),
	  axis.title   = element_text(size=10, color="#555555"),
	  axis.text    = element_text(size=8, color="#555555"),
	  axis.ticks.y = element_blank(),
	  axis.title.x = element_text(vjust=-1),
	  axis.title.y = element_text(vjust= 1),
	  axis.ticks.x = element_line(color="#e3e3e3", size=.2),
	  plot.margin = unit(c(0,1,.5,.5), "cm"))
direct.label(p, list(last.points, cex=.8, alpha=1, hjust = 0, vjust = -.75))
ggsave("figs/approve_rasmussen.png")

# Plot % McCain: R vs. Rest 
election$rasmussen <- ifelse(election$organization=="Rasmussen ", "Rasmussen", "Other")

p <- 
ggplot(data=election, aes(x=week, y=mccain, col=rasmussen)) +
geom_point(alpha = .3) +
geom_smooth() + 
scale_colour_manual(values = c("#999999", "#bb7777")) + 
scale_y_continuous("Percent Favoring McCain") + 
scale_x_continuous("Week of the campaign", lim=c(0, 101)) + 
theme_minimal() +
theme(panel.grid.major  = element_line(color="#e7e7e7",  linetype = "dotted"),
	  panel.grid.minor  =  element_blank(),
	  legend.position   = "none",
	  axis.title   = element_text(size=10, color="#555555"),
	  axis.text    = element_text(size=8, color="#555555"),
	  axis.ticks.y = element_blank(),
	  axis.title.x = element_text(vjust=-1),
	  axis.title.y = element_text(vjust= 1),
	  axis.ticks.x = element_line(color="#e3e3e3", size=.2),
	  plot.margin = unit(c(0,1,.5,.5), "cm"))
direct.label(p, list(last.points, cex=.8, alpha=1, hjust = -.1, vjust = -.75))
ggsave("figs/mccain_rasmussen.png")

