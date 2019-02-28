# Processing OMOP Clinical Notes with Amazon Comprehend Medical
Gain medical insights from clinical notes stored in the OMOP Common Data Model using the Amazon Comprehend Medical NLP service.

This R code can be used to read clinical notes from the OMOP 'note' table, process them using [Amazon Comprehend Medical](https://aws.amazon.com/comprehend/medical/), and write them into the OMOP 'note_nlp' table.  The high-level architecture used to do this is shown below.

![diagram](https://github.com/aws-samples/amazon-comprehend-medical-omop-notes-mapping/raw/master/images/omop-cm-notes-arch.png)

You can quickly deploy [an OHDSI environment on AWS environment](https://github.com/JamesSWiggins/ohdsi-cfn) from which you can execute this code or you can also use this code from outside of AWS to call Amazon Comprehend Medical.  If you deploy the OHDSI environment on AWS using the automation linked above, there is no additional configuration needed to use Comprehend Medical.  If you want to use it outside of AWS, you only need to configure a credentials file that allows this code to call the Comprehend Medical service.  You can [find instructions for doing that here.](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html)

An example of the type of mapping Amazon Comprehemend Medical provides and the corresponding 'note_nlp' records are show below.
![diagram](https://github.com/aws-samples/amazon-comprehend-medical-omop-notes-mapping/blob/master/images/omop-cm-mapping.png)

