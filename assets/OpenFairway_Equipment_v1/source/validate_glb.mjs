// Khronos validator plus catalog coverage, shared geometry, embedded textures and bounds.
// npm install gltf-validator; node validate_glb.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const validator=require(process.env.OFG_VALIDATOR_MODULE || 'gltf-validator');
const root=path.resolve(path.dirname(new URL(import.meta.url).pathname),'..');
const assets=path.join(root,'assets/openfairway_equipment');
const catalog=JSON.parse(fs.readFileSync(path.join(assets,'catalog.json')));
const issues=[];const geometry={};const reports=[];
for(const item of [...catalog.items,...catalog.props]){
  const file=path.join(root,item.model.replace('res://',''));
  const buffer=fs.readFileSync(file);
  const report=await validator.validateBytes(new Uint8Array(buffer),{uri:path.basename(file),maxIssues:100});
  const jsonLength=buffer.readUInt32LE(12);
  const gltf=JSON.parse(buffer.subarray(20,20+jsonLength).toString());
  const binStart=20+jsonLength+8;
  if(report.issues.numErrors)issues.push({id:item.id,errors:report.issues.messages.filter(x=>x.severity===0)});
  if((gltf.images||[]).some(x=>x.uri))issues.push({id:item.id,error:'External image reference'});
  const headNode=gltf.nodes.find(n=>n.name?.endsWith('__head'));
  if(headNode){
    const mesh=gltf.meshes[headNode.mesh];
    const accessor=gltf.accessors[mesh.primitives[0].attributes.POSITION];
    const view=gltf.bufferViews[accessor.bufferView];
    const data=buffer.subarray(binStart+(view.byteOffset||0)+(accessor.byteOffset||0),binStart+(view.byteOffset||0)+(accessor.byteOffset||0)+accessor.count*12);
    const hash=crypto.createHash('sha256').update(data).digest('hex');
    (geometry[item.family]??=[]).push({id:item.id,hash});
    if(item.family!=='putter'&&item.total_triangles>1800)issues.push({id:item.id,error:'Non-putter exceeds full club triangle budget'});
    if(item.family==='putter'&&item.head_triangles>2200)issues.push({id:item.id,error:'Putter head exceeds triangle budget'});
    for(const primitive of mesh.primitives){
      if(primitive.attributes.NORMAL===undefined||primitive.attributes.TEXCOORD_0===undefined||primitive.attributes.TANGENT===undefined)issues.push({id:item.id,error:'Missing head normals, UV or tangent'});
    }
  }
  reports.push({id:item.id,errors:report.issues.numErrors,warnings:report.issues.numWarnings,infos:report.issues.numInfos,bytes:buffer.length,messages:report.issues.messages.filter(x=>x.severity<2)});
}
for(const [family,entries] of Object.entries(geometry)){
  const count=new Set(entries.map(x=>x.hash)).size;
  if(family==='putter'?count!==9:count!==1)issues.push({family,error:'Unexpected shared-geometry count',count});
}
const ids=new Set(catalog.items.map(x=>x.id));
if(ids.size!==45)issues.push({error:'Expected 45 unique catalog IDs',count:ids.size});
if(catalog.items.filter(x=>x.collectible).length!==7)issues.push({error:'Expected seven collectible putters'});
const result={validator:'Khronos glTF Validator',assets:reports.length,inventory_items:ids.size,shared_head_geometry_counts:Object.fromEntries(Object.entries(geometry).map(([k,v])=>[k,new Set(v.map(x=>x.hash)).size])),issues,reports};
fs.writeFileSync(path.join(root,'validation_report.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify({assets:reports.length,issues,errors:reports.reduce((n,x)=>n+x.errors,0),warnings:reports.reduce((n,x)=>n+x.warnings,0),geometry:result.shared_head_geometry_counts},null,2));
if(issues.length)process.exitCode=1;
