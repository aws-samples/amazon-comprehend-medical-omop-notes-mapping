#Source the DatabaseConnector::connect() call for my OMOP database
source("~/omop-connection.R")
cdmDatabaseSchema <- "CMSDESynPUF1k"

#Show the contents of the OMOP Notes table
View(DatabaseConnector::querySql(connectionDetails, paste0("SELECT * FROM ",cdmDatabaseSchema,".note")))

#Reticulate is used to run Python code from within R
library(reticulate)
#httr is used to make HTTP GET calls to SNOMED or RxNorm
library(httr)
#jsonlite is used to parse the JSON response from the SNOMED or RxNorm servers.
library(jsonlite)

#source the Python code to call Comprehend Medical
e <- environment()
reticulate::source_python('call_comprehend_medical.py', envir = e)

#Set the minimum confidence score an inference must meet from Amazon Comprehend Medical to be added to the NOTE_NLP table.
min_score <- 0.80


#Set the constants for the  REST interface for search the SNOMED ontology
base <- "https://browser.ihtsdotools.org/"
endpoint <- "api/snomed/en-edition/v20180131/descriptions"

# Get a list of all the notes in the note table in 'noteids'
noteids <- DatabaseConnector::querySql(connectionDetails, paste0("SELECT DISTINCT note_id FROM ", cdmDatabaseSchema,".note"))
noteids <- unlist(noteids)

#Get the largest note_nlp_id table primary key so we can begin writing new NOTE_NLP records that don't overlap with previous ones.
note_nlp_id <- DatabaseConnector::querySql(connectionDetails, paste0("SELECT MAX(note_nlp_id) FROM ", cdmDatabaseSchema,".note_nlp"))
note_nlp_id <- unlist(note_nlp_id)
if (is.na(note_nlp_id)){
  note_nlp_id <- 0
}


#for each note in the NOTE table:
for (i in noteids) {
  #Read the note from the NOTE table
  omop_note <- DatabaseConnector::querySql(connectionDetails, paste0("SELECT note_text FROM ",cdmDatabaseSchema,".note WHERE note_id=",i,";"))
  omop_note <- unlist(omop_note[1])
  omop_note <- unlist(omop_note[1])
  print(paste0('Now processing Note ID = ',i))
  print(omop_note)
  
  #Call Amazon Comprehend Medical to extract the relevant medical information
  entities <- call_comprehend_medical(omop_note)

  #for each detected medical 'entity' in the note:
  for (entity in entities) {
    term_modifiers <- ""
    
    #if the entity is PHI, or if it doesn't meet our confidence threshold, don't write it to NOTE_NLP
    if (entity$Category != "PROTECTED_HEALTH_INFORMATION" && entity$Score >= min_score) {
      #Pass the detected medical entity to the SNOMED REST interface to get the matching SNOMED code.
      snomed_call <- paste(base,endpoint,"?","query","=", entity$Text,"&limit=1&searchMode=partialMatching&lang=english&statusFilter=activeOnly&skipTo=0&returnLimit=1&normalize=true", sep="")
      get_snomed <- GET(snomed_call, type = "basic")
      get_snomed_text <- content(get_snomed, "text")
      
      #IF the SNOMED REST interface didn't return an error
      if (!grepl("Error", get_snomed_text, fixed=TRUE)){
        #Extract the SNOMED code from the JSON that was returned from the SNOMED REST interface
        get_snomed_text <- fromJSON(get_snomed_text, flatten = TRUE)
        get_snomed_code <- get_snomed_text$matches$conceptId
        
        #IF a SNOMED code was returned
        if (!is.null(get_snomed_code)) {
          #Search the OMOP Vocabulary to find the matching Standard Concept ID for that SNOMED code.
          standard_concept_id <- DatabaseConnector::querySql(connectionDetails, paste0("SELECT CONCEPT_ID FROM ",cdmDatabaseSchema,".concept WHERE concept_code=",get_snomed_code,";"))
          standard_concept_id <- unlist(standard_concept_id)[1]
          
          #IF a Standard Concept code was found for the SNOMED code
          if (!is.na(standard_concept_id)) {
            #Write the 'Category' detected by Amazon Comprehend Medical into the 'term_modifiers' field
            term_modifiers <- paste(entity$Category, term_modifiers, sep=" ")
            #Also, write any 'Traits' detected by Amazon Comprehend Medical into the 'term_modifiers' field
            for (trait in entity$Traits) {
              if (trait$Score >= min_score) {
                term_modifiers <- paste(trait$Name, term_modifiers, sep=" ")
              }
            }
            #Also, write any 'Attributes' detected by Amazon Comprehend Medical into the 'term_modifiers' field
            for (attribute in entity$Attributes){
              if (attribute$Score >= min_score){
                term_modifiers <- paste(attribute$Text, term_modifiers, sep=" ")
                for (attribute_trait in attribute$Traits) {
                  if (attribute_trait$Score >= min_score) {
                    term_modifiers <- paste(attribute_trait$Name, term_modifiers, sep=" ")
                  }
                }
              }
            }
            
            #Finally, write the a new record to the NOTE_NLP table with the following field mapping
            # offset: The character offset within the note, provided by Amazon Comprehend Medical, for the detected medically relevant text 
            # lexical_variant: The actual medically relevant text detected by Amazon Comprehend Medical (called 'Text' in the returned JSON)
            # note_nlp_concept_id: The OMOP Standard Concept Code, derived from the mapping of the 'lexical_variant' to SNOMED by the REST call, then to OMOP by searching the vocabulary
            # note_nlp_source_concept_id: 0 because our source notes do not contain concept ids
            # nlp_system: Amazon Comprehend Medical
            # nlp_date: sysdate() function returning the current date/time when the note was processed
            # term_modifiers: space delimited combination of the Category, Traits, and Attributes detected by Amazon Comprehend Medical.  This can contain information like Negation, associated dosages, frequecy, etc. related to the 'lexical_variant'
            print(paste0("Writing note_nlp record, ",note_nlp_id,"... Standard Concept ID:", standard_concept_id,", Lexical Variant: ", entity$Text,", Term Modifiers: ", term_modifiers))
            DatabaseConnector::executeSql(connectionDetails, paste0("INSERT INTO ",cdmDatabaseSchema,".note_nlp (note_nlp_id, note_id, section_concept_id, \"offset\", lexical_variant, note_nlp_concept_id, note_nlp_source_concept_id, nlp_system, nlp_date, term_modifiers) VALUES (",note_nlp_id,", ",i,", 0, '",entity$BeginOffset,"', '",entity$Text,"', ",standard_concept_id,", 0, 'Amazon Comprehend Medical', sysdate, '",term_modifiers,"');"))
            note_nlp_id <- note_nlp_id+1
          }
        }
      }
    }
  }
}


#Print interesting fields from the NOTE_NLP table
View(DatabaseConnector::querySql(connectionDetails, paste0("SELECT note_nlp_id, note_id, \"offset\", lexical_variant, note_nlp_concept_id,nlp_system, term_modifiers FROM ",cdmDatabaseSchema,".note_nlp;")))

