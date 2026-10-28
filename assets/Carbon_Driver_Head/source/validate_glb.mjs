import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url);
const validator=require(process.env.GLTF_VALIDATOR_MODULE || 'C:/Users/willi/driver_work/validation/node_modules/gltf-validator');
const pack=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const reports=[];
for(const name of ['driver_head_real_scale.glb','driver_head_shaft_attachment.glb']){
 const bytes=fs.readFileSync(path.join(pack,name));
 const result=await validator.validateBytes(new Uint8Array(bytes),{uri:name,maxIssues:1000});
 reports.push({file:name,bytes:bytes.length,...result});
}
const summary={validator:'Khronos glTF Validator',errors:reports.reduce((n,r)=>n+r.issues.numErrors,0),warnings:reports.reduce((n,r)=>n+r.issues.numWarnings,0),reports};
fs.writeFileSync(path.join(pack,'glTF_validation.json'),JSON.stringify(summary,null,2));
console.log(JSON.stringify({errors:summary.errors,warnings:summary.warnings,reports:reports.map(r=>({file:r.file,issues:r.issues}))}));
if(summary.errors)process.exitCode=1;
