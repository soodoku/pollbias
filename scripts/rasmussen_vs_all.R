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

# Plot approval: R vs. Rest 
ggplot(data=approve, aes(x=week, y=approve, col=organization=="Rasmussen")) +
geom_point(alpha = .3) +
geom_smooth() + 
scale_colour_manual(values = c("#999999", "#bb7777")) + 
scale_y_continuous("% Approving Bush") + 
scale_x_continuous("Week of the presidency") + 
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
ggsave("figs/approve_rasmussen.png")

# Plot % McCain: R vs. Rest 
ggplot(data=election, aes(x=week, y=mccain, col=organization=="Rasmussen ")) +
geom_point(alpha = .3) +
geom_smooth() + 
scale_colour_manual(values = c("#999999", "#bb7777")) + 
scale_y_continuous("% in favor of McCain") + 
scale_x_continuous("Week of the campaign") + 
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
ggsave("figs/mccain_rasmussen.png")

