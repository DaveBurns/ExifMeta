local metaDefs = {}

metaDefs[#metaDefs + 1] = { id='lastUpdate', title='ExifMeta Updated', version=1, dataType='string', searchable=true, browsable=true }
metaDefs[#metaDefs + 1] = { id='lastUpdate_' }
metaDefs[#metaDefs + 1] = { id='bigBlock', title='Exif Metadata', version=2, dataType='string', readOnly=false, searchable=false, browsable=false }

return {
    metadataFieldsForPhotos = metaDefs,
    schemaVersion = 1,
}