import boto3
import glob
import os
import pandas as pd
from decimal import *

def call_comprehend_medical (note_text):
  client = boto3.client(service_name='comprehendmedical', region_name='us-east-1')
  result = client.detect_entities(Text = r.omop_note)
  entities = result['Entities'];

  return entities
  
