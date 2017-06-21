local metaDefs = {}
metaDefs[#metaDefs + 1] = { id='lastUpdate', title='ExifMeta Updated', version=1, dataType='string', searchable=true, browsable=true }
metaDefs[#metaDefs + 1] = { id='lastUpdate_' }


return {
  metadataFieldsForPhotos = metaDefs,
  schemaVersion = 1,
}