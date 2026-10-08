#ifndef SWGXR_TERRAIN_MODIFICATION_H
#define SWGXR_TERRAIN_MODIFICATION_H
#include "templates/building/SharedBuildingObjectTemplate.h"
#include "templates/footprint/StructureFootprint.h"
// Original authored client terrain layer; this is metadata, never a replacement
// height or an inferred rectangular flattening operation.
class SwgxrTerrainModification {
public:
 static void describe(SceneObject* object,JSONSerializationType& row){
  auto source=object->getObjectTemplate();auto building=dynamic_cast<SharedBuildingObjectTemplate*>(source);
  row["terrain_modification_file"]=building?std::string(building->getTerrainModificationFile().toCharArray()):"";
  row["snap_to_terrain"]=source->getSnapToTerrain();row["clear_flora_radius"]=source->getClearFloraRadius();row["footprint"]=nullptr;
  auto tangible=dynamic_cast<SharedTangibleObjectTemplate*>(source);auto footprint=tangible?tangible->getStructureFootprint():nullptr;
  if(footprint)row["footprint"]={{"rows",footprint->getRowSize()},{"columns",footprint->getColSize()},{"center_x",footprint->getCenterX()},{"center_z",footprint->getCenterY()},{"row_chunk_size",footprint->getRowChunkSize()},{"column_chunk_size",footprint->getColChunkSize()}};
 }
};
#endif
