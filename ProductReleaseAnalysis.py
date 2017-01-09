""" 
Data Validation for PLS2016
Michael Miranda
20161129


The purpose of this is to cross check if releases for files the user said 
to migrate are being migrated themself.
"""


import os
import pandas as pd

data_dir = "C:/Users/micmiran/Desktop/New folder/Upload Spreadsheets/Complete/RM Response"
upload_dir = "C:/Users/micmiran/Desktop/New folder/Upload Spreadsheets/Complete"
release = pd.DataFrame()
products = pd.DataFrame()
upload_notes = pd.DataFrame()
master_list = pd.DataFrame()


#loading all files within a folder. they all need to be the same format for this to work
rm_files = [ f for f in os.listdir(data_dir) if os.path.isfile(os.path.join(data_dir,f)) ]
#only grabbing xlsx files
rm_files = [s for s in rm_files if ".xlsx" in s]

   

#loading releases into pandas....
for n in range(len(rm_files)):
    rm_file_name = data_dir+'/'+rm_files[n]
    rm_file = pd.ExcelFile(rm_file_name)
    try:
        #look for releases
        rm_file_release_sheetname = [s for s in rm_file.sheet_names if "Release" in s]
        rm_file_release = rm_file.parse(rm_file_release_sheetname[0])
        #look for products
        rm_file_product_sheetname = [s for s in rm_file.sheet_names if "Product" in s]
        rm_file_product = rm_file.parse(rm_file_product_sheetname[0])
    except:
        rm_file_release = rm_file.parse(rm_file.sheet_names[len(rm_file.sheet_names) - 0])
        rm_file_product = rm_file.parse(rm_file.sheet_names[len(rm_file.sheet_names) - 1])
    #cleaning up columns
    rm_file_release.columns = map(str.lower, rm_file_release.columns)
    rm_file_release = rm_file_release.rename(columns=lambda x: x.replace('_', ' '))
    rm_file_release = rm_file_release.rename(columns=lambda x: x.replace(' ', ''))
    rm_file_release = rm_file_release.rename(columns=lambda x: x.replace('comments', 'notes'))
    rm_file_product.columns = map(str.lower, rm_file_product.columns)
    rm_file_product = rm_file_product.rename(columns=lambda x: x.replace('_', ' '))
    rm_file_product = rm_file_product.rename(columns=lambda x: x.replace(' ', ''))
    rm_file_product = rm_file_product.rename(columns=lambda x: x.replace('comments', 'notes'))    
    #inserting the sheets into a master list
    release = release.append(rm_file_release)
    products = products.append(rm_file_product)


    

#loading products into pandas    



#we have to load the upload sheets one by one and create a new file
#loading all files within a folder. they all need to be the same format for this to work
upload_files = [ f for f in os.listdir(upload_dir) if os.path.isfile(os.path.join(upload_dir,f)) ]
#only grabbing xlsx files
upload_files = [s for s in upload_files if ".xlsx" in s]


for n in range(len(upload_files)):
    upload_file_name = upload_dir+'/'+upload_files[n]
    #using upload sheet as the base
    upload = pd.read_excel(open(upload_file_name,'rb'), sheetname=0)

    #joining to release...
    upload_release = pd.merge(upload, release, how='left', 
                             left_on= upload['Release Name'].map(str) + upload['Release Version'].map(str),
                             right_on=release['releasename'].map(str) + release['releaseversion'].map(str))
    
    upload_product = pd.merge(upload_release, products, how='left', 
                             left_on= upload_release['productname'].map(str),
                             right_on=products['productname'].map(str),
                             suffixes=('_r','_p'))
    

    
    upload_final = upload_product[['productname_p',
                                   'Release Name',
                                   'Release Version',
                                   'Fileset Part Number',
                                   'rmnotes_r',
                                   'rmnotes_p']]
                                   
    upload_final = upload_final.rename(columns= { 'productname_p' : 'Product Name',
                                                  'rmnotes_r' : 'RM Release Notes',
                                                  'rmnotes_p' : 'RM Product Notes'})                                   
    
    #files with new products, like documentation etc, are getting duplicated..fixing this
    upload_final = upload_final.drop_duplicates(keep='first')

    upload_notes = upload_final.dropna(subset=['RM Release Notes'])
    upload_notes = upload_notes.append(upload_final.dropna(subset=['RM Product Notes']))
    upload_notes = upload_notes.drop_duplicates(keep='first')
    master_list = master_list.append(upload_notes)
    

    writer = pd.ExcelWriter(upload_dir+'/Finished Files/'+upload_files[n]+' With Release RM Notes.xlsx')
    upload_notes.to_excel(writer, 'Lines with Notes',index=False)
    upload_final.to_excel(writer, 'Upload Sheet with Release Note',index=False)
    upload.to_excel(writer, 'Upload Sheet', index=False)
    writer.save()
    
    
    
writer2 = pd.ExcelWriter(upload_dir+'/Finished Files/'+'All lines with notes.xlsx')    
master_list.to_excel(writer2, index=False)
writer2.save()
