library(ggmap)
library(maps)
library(ggplot2)
library(dplyr)
library(zipcode)
library(plyr)
library(viridis)
library(maptools)
library(rgdal)
library(foreign)
library(classInt)
library(scales)
library(rgeos)
library(shinydashboard)
library(leaflet)

#setwd("~/Documents/R files/BDT de-identified work/Benephilly_map/data")

data(zipcode)
zipcode$zip <- as.numeric(zipcode$zip)
str(zipcode)



zips <- read.csv("data/Shapefiles_dbfedit1.csv",stringsAsFactors = FALSE)
#zips <- subset(zips, benefit_key != c("aca_qhp_pa", "pace" , 
#"head_start_pa", "wic" ,"medicaid_pa_recert", "eitc" ,"ccis_pa" ,"head_start_pa", "eitc_pa" ,
#"unemployment" , "aca_qhp_pa" , "cap_pa"))
zips[,c(1,3)] <- NULL
zips1 <- zips
colnames(zips1) <- c("zip", "benefit_key" , "clients_served")
zips1<- merge(zips1, zipcode, by='zip')

philly_shp <- readOGR("data/Zipcodes_Poly.shp")
philly_shp@data$CLIENTS_SE <- NULL
philly_shp@data$id <- rownames(philly_shp@data)
philly_shp.point <- fortify(philly_shp, region="id")
philly_shp.df <- inner_join(philly_shp.point,philly_shp@data, by="id")
philly_shp.df <- suppressWarnings(left_join(philly_shp.df, zips, by="CODE"))
philly_shp.df$clients_served <- as.numeric(philly_shp.df$clients_served)
head(philly_shp.df)
str(philly_shp.df)
philly_shp.df <- philly_shp.df[,c(1,2,7,9,11,12)]
ggplot(philly_shp.df, aes(long, lat, group=group )) + geom_polygon()

zips2 <- zips1[! zips1$zip %in% c(19105,19193, 19102),]
zips1b <- zips1[,1:3]

bounds<-bbox(philly_shp)

## custom label format function
myLabelFormat = function(..., reverse_order = FALSE){ 
  if(reverse_order){ 
    function(type = "numeric", cuts){ 
      cuts <- sort(cuts, decreasing = T)
    } 
  }else{
    labelFormat(...)
  }
}

ui <- dashboardPage(
  header<-dashboardHeader(title="Benephilly Clients Served by Zipcode",
                          titleWidth = 600),
  dashboardSidebar(disable = TRUE),
  body<-dashboardBody(
    fluidRow(
      column(width = 5,
             box(width = NULL, solidHeader = TRUE,
                 leafletOutput("leafMap", height=400)
             )
      ),
      column(width=4,box(width = NULL, solidHeader = TRUE,
                         plotOutput("map", height=400)
      )),
      column(width=3,
             box(width=NULL, 
                 img(src="bdtlogo.png", width="100%", height=100, align="center"),
                 uiOutput("BenefitOutput"))),
                 
      fluidRow(column(width=9,
                      box(width=NULL,
                          dataTableOutput("results")
                      )
                      
                      ))
          
                 
                 
             )
      )
    )
  

server <- function(input, output, session) {
  
  output$BenefitOutput <- renderUI({
    selectInput("BenefitInput", "Choose a Benefit you want to map:",
                sort(unique(zips2$benefit_key)),
                selected = "snap")}) 
  
  filtered <- reactive({
    if (is.null(input$BenefitInput)) {
      return(NULL)
    } 
    philly_shp.df %>%
      filter(benefit_key== input$BenefitInput ,
             CODE==CODE,
             clients_served== clients_served,
             group==group,
             long==long,
             lat==lat)})
  
  tabledata <- reactive({
    if (is.null(input$BenefitInput)) {
      return(NULL)
    } 
    zips1b %>%
      filter(benefit_key== input$BenefitInput ,
             zip==zip,
             clients_served== clients_served)})
  
  output$map <- renderPlot({
    if (is.null(filtered())) {
      return()
    }
    ggplot() + 
      geom_polygon(data = philly_shp.df, 
                   aes(x = long, y = lat, group = group), 
                   color = "black", size = 0.25) +
      geom_polygon(data = filtered(), 
                   aes(x = long, y = lat, group = group, fill = clients_served), 
                   color = "black", size = 0.25) + 
      scale_fill_distiller(name="Clients Served", palette = "YlGn", breaks = pretty_breaks(n = 6))+
      theme_nothing(legend = TRUE)+
      geom_text(data=zips2, aes(longitude,latitude,label=zip), color="grey",
                size=2,fontface="bold")+
      labs(title="Clients Served by Zipcode")
  })
  

  output$results <- renderDataTable(tabledata())
  
  
  #leaflet portion
  
  getDataSet<-reactive({
    
    # Get a subset of the income data which is contingent on the input variables
    zips_subset<- subset(zips1b,benefit_key==input$BenefitInput)
    zips_subset <- rename(zips_subset,c('zip'='CODE'))
    
    # Copy our GIS data
    joinedDataset<-philly_shp
    
    # Join the two datasets together
    joinedDataset@data <- suppressWarnings(left_join(joinedDataset@data, zips_subset, by="CODE"))
    joinedDataset@data$clients_served <- as.numeric(joinedDataset@data$clients_served)
    #joinedDataset$clients_served[is.na(joinedDataset$clients_served)] <- 0
    #joinedDataset$benefit_key[is.na(joinedDataset$benefit_key)] <- input$BenefitInput
    joinedDataset@data <- na.omit(joinedDataset@data)
    
    joinedDataset
  })
  
  output$leafMap<-renderLeaflet({
    
    leaflet() %>%
      addTiles() %>%
      
      # Centre the map in the middle of our co-ordinates
      setView(mean(bounds[1,]),
              mean(bounds[2,]),
              zoom=10 # set to 10 as 9 is a bit too zoomed out
      )       
    
  })
  
  
  
  observe({
    theData<-getDataSet() 
    
    # colour palette mapped to data
    pal <- colorQuantile(rev("YlGn"), theData$clients_served, n = 6) 
    
    # set text for the clickable popup labels
    philly_popup <-paste0("<strong> Zipcodes </strong>", 
                          theData$CODE, 
                          "<br><strong> Clients served per zipcode </strong>", 
                          theData$clients_served)
    
    # If the data changes, the polygons are cleared and redrawn, however, the map (above) is not redrawn
    leafletProxy("leafMap", data = theData) %>%
      clearShapes() %>%
      addProviderTiles("CartoDB.Positron") %>%
      addPolygons(data = theData,
                  fillColor = pal(theData$clients_served), 
                  fillOpacity = 0.8, 
                  color = "#BDBDC3", 
                  weight = 2,
                  popup = philly_popup)  
    
  })
  
  observe({
    theData <- getDataSet()
    pal2 <- colorNumeric("YlGn", theData$clients_served, n=6)
    proxy <- leafletProxy("leafMap", data = theData)
    
    # Remove any existing legend, and only if the legend is
    # enabled, create a new one.
    proxy %>% clearControls()
      pal <- pal2
      proxy %>% addLegend(position = "bottomright",
                          pal = pal, values = ~clients_served , opacity = 1,
                          title = 'Legend',
                          labFormat = myLabelFormat(reverse_order = T)
      )
    
  })
  
  
  
}

shinyApp(ui = ui, server = server)
