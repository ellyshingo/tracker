// Тест функции drive без Google и Supabase: node --experimental-strip-types supabase/functions/drive/test.mjs
const ENV={GOOGLE_CLIENT_ID:"c",GOOGLE_CLIENT_SECRET:"s",GOOGLE_REFRESH_TOKEN:"r",DRIVE_ROOT_FOLDER_ID:"ROOT",SUPABASE_URL:"https://sb",SUPABASE_ANON_KEY:"anon",SUPABASE_SERVICE_ROLE_KEY:"svc"};
let H;globalThis.Deno={env:{get:k=>ENV[k]},serve:h=>{H=h}};
// fake DB + Drive
const students={a:{id:"a",name:"Айбек",folder:null,email:"a@x.kg"},b:{id:"b",name:"Бермет",folder:"FB",email:"b@x.kg"}};
const users={"Bearer A":{role:"student",sid:"a",email:"a@x.kg"},"Bearer B":{role:"student",sid:"b",email:"b@x.kg"},"Bearer C":{role:"staff",email:"cur@gg.kg"}};
let n=0;const files={ROOT:{id:"ROOT",mimeType:"application/vnd.google-apps.folder",name:"root",parents:[]},
 FB:{id:"FB",mimeType:"application/vnd.google-apps.folder",name:"Бермет",parents:["ROOT"]},
 SUB:{id:"SUB",mimeType:"application/vnd.google-apps.folder",name:"Старое",parents:["FB"]},
 rec:{id:"rec",name:"Рекомендация.pdf",mimeType:"application/pdf",parents:["FB"],appProperties:{gg_vis:"0",gg_cat:"Рекомендательное письмо"}},
 pass:{id:"pass",name:"Паспорт.jpg",mimeType:"image/jpeg",parents:["SUB"]},
 gdoc:{id:"gdoc",name:"Эссе",mimeType:"application/vnd.google-apps.document",parents:["FB"],appProperties:{gg_vis:"1"}},
 other:{id:"other",name:"чужое.pdf",mimeType:"application/pdf",parents:["ROOT"],appProperties:{gg_vis:"1"}}};
let tokenCalls=0;
globalThis.fetch=async(url,init={})=>{url=String(url);const J=(o,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{"content-type":"application/json"}});
 if(url.startsWith("https://oauth2")){tokenCalls++;return J({access_token:"tok",expires_in:3600})}
 if(url.startsWith("https://sb/rest/v1/rpc/")){const fn=url.split("/").pop();const u=users[init.headers.Authorization];const a=JSON.parse(init.body);
   if(!u)return J({message:"jwt"},401);
   if(fn==="tracker_is_staff")return J(u.role==="staff");
   if(fn==="drive_access"){let sid=a.sid;if(u.role!=="staff"){if(sid&&sid!==u.sid)return J(null);sid=u.sid}const s=students[sid];if(!s)return J(null);return J({role:u.role,id:s.id,name:s.name,folderId:s.folder,email:u.email})}
   if(fn==="drive_set_folder"){if(u.role!=="staff")return J({message:"not allowed"},403);students[a.sid].folder=a.fid;return J(null)}}
 if(url.startsWith("https://sb/rest/v1/tracker_students")){if(init.headers.Authorization!=="Bearer svc")return J({},401);const id=decodeURIComponent(url.split("eq.")[1]);students[id].folder=JSON.parse(init.body).drive_folder_id;return new Response(null,{status:204})}
 if(init.headers?.Authorization!=="Bearer tok")return J({error:{message:"auth"}},401);
 const u=new URL(url);
 if(u.pathname==="/upload/drive/v3/files"){const txt=await new Response(init.body).text();const meta=JSON.parse(txt.split("\r\n\r\n")[1].split("\r\n")[0]);const id="up"+(++n);files[id]={id,...meta,mimeType:"text/plain",size:"5",trashed:false};return J(files[id])}
 if(u.pathname==="/drive/v3/files"&&init.method==="POST"){const m=JSON.parse(init.body);const id="F"+(++n);files[id]={id,...m};return J(files[id])}
 if(u.pathname==="/drive/v3/files"){const pid=u.searchParams.get("q").match(/'(.+?)'/)[1];return J({files:Object.values(files).filter(f=>(f.parents||[]).includes(pid)&&!f.trashed)})}
 const m=u.pathname.match(/^\/drive\/v3\/files\/([^/]+)(\/export)?$/);
 if(m){const f=files[decodeURIComponent(m[1])];if(!f)return J({error:{message:"nf"}},404);
   if(init.method==="PATCH"){const b=JSON.parse(init.body);if(b.appProperties)f.appProperties={...f.appProperties,...b.appProperties};if(b.trashed)f.trashed=true;return J({id:f.id})}
   if(m[2])return new Response("PDF-"+f.name);if(u.searchParams.get("alt")==="media")return new Response("DATA-"+f.name);return J(f)}
 return J({error:{message:"unmocked "+url}},500)};
await import("./index.ts");
const call=async(tok,body)=>{const isF=body instanceof FormData;const r=await H(new Request("https://fn/drive",{method:"POST",headers:{Authorization:tok,...(isF?{}:{"Content-Type":"application/json"})},body:isF?body:JSON.stringify(body)}));const ct=r.headers.get("content-type")||"";return {s:r.status,d:ct.includes("json")?await r.json():await r.text(),h:r.headers}};
let fails=0;const ok=(c,m)=>{console.log((c?"ok  ":"FAIL")+" "+m);if(!c)fails++};
let r;
r=await call("Bearer C",{action:"list",studentId:"b"});ok(r.s===200&&r.d.files.length===3,"staff sees 3 files incl subfolder: "+r.d.files.map(f=>f.path+f.name).join(", "));ok(r.d.files.every(f=>"link"in f),"staff gets links");
r=await call("Bearer B",{action:"list"});ok(r.s===200&&r.d.files.length===1&&r.d.files[0].id==="gdoc","student b sees only visible: "+JSON.stringify(r.d.files.map(f=>f.name)));ok(!("link"in r.d.files[0])&&!r.d.folderUrl,"student gets no drive links");
r=await call("Bearer B",{action:"download",fileId:"rec"});ok(r.s===403,"student cannot download hidden rec letter");
r=await call("Bearer B",{action:"download",fileId:"other"});ok(r.s===403,"student cannot download file outside folder");
r=await call("Bearer C",{action:"download",studentId:"b",fileId:"other"});ok(r.s===403,"staff cannot download outside-folder via student b");
r=await call("Bearer B",{action:"download",fileId:"gdoc"});ok(r.s===200&&r.d==="PDF-Эссе"&&decodeURIComponent(r.h.get("x-file-name"))==="Эссе.pdf","google doc exported to pdf");
r=await call("Bearer C",{action:"download",studentId:"b",fileId:"pass"});ok(r.s===200&&r.d==="DATA-Паспорт.jpg","staff downloads nested file");
r=await call("Bearer C",{action:"folders"});ok(r.s===200&&r.d.folders.length===1&&r.d.folders[0].id==="FB"&&r.d.folders[0].name==="Бермет","staff lists root folders only (no files, no subfolders)");
r=await call("Bearer A",{action:"folders"});ok(r.s===403,"student cannot list root folders");
r=await call("Bearer C",{action:"link",studentId:"a",folder:"FBFBFBFBFBFB"});ok(r.s===404,"link by bare unknown id → 404");
r=await call("Bearer A",{action:"list",studentId:"b"});ok(r.s===403,"student a cannot list b");
r=await call("Bearer A",{action:"list"});ok(r.s===200&&r.d.folderId===null,"a no folder yet");
r=await call("Bearer A",{action:"create"});ok(r.s===403,"student cannot create via action");
r=await call("Bearer A",{action:"link",folder:"FB"});ok(r.s===403,"student cannot link folder");
let fd=new FormData();fd.append("action","upload");fd.append("category","Паспорт");fd.append("visible","0");fd.append("file",new Blob(["hello"],{type:"text/plain"}),"scan.txt");
r=await call("Bearer A",fd);ok(r.s===200&&students.a.folder&&files[students.a.folder].parents[0]==="ROOT","student upload lazily creates folder (svc): "+students.a.folder);
const up=r.d.file;ok(up.visible&&up.byStudent&&up.name==="Паспорт — scan.txt","student upload visible+named: "+up.name);
r=await call("Bearer A",{action:"list"});ok(r.d.files.length===1,"a sees own upload");
r=await call("Bearer B",{action:"delete",fileId:up.id});ok(r.s===403,"b cannot delete a's file");
r=await call("Bearer B",{action:"delete",fileId:"gdoc"});ok(r.s===403,"student cannot delete staff file");
r=await call("Bearer C",{action:"visibility",studentId:"b",fileId:"rec",visible:true});ok(r.s===200&&files.rec.appProperties.gg_vis==="1","staff toggles visibility");
r=await call("Bearer B",{action:"visibility",fileId:"gdoc",visible:false});ok(r.s===403,"student cannot toggle visibility");
r=await call("Bearer A",{action:"delete",fileId:up.id});ok(r.s===200&&files[up.id].trashed,"student deletes own upload");
fd=new FormData();fd.append("action","upload");fd.append("studentId","b");fd.append("category","Рекомендательное письмо");fd.append("file",new Blob(["x"]),"rec2.pdf");
r=await call("Bearer C",fd);ok(r.s===200&&!r.d.file.visible&&files[r.d.file.id].parents[0]==="FB","staff upload hidden by default");
fd=new FormData();fd.append("action","upload");fd.append("file",new Blob([new Uint8Array(26*1024*1024)]),"big.bin");
r=await call("Bearer A",fd);ok(r.s===413,"size limit");
r=await call("Bearer C",{action:"link",studentId:"a",folder:"https://drive.google.com/drive/folders/SUB?usp=sharing"});ok(r.s===400||r.s===200,"link parse SUB (short id) status "+r.s);
r=await call("Bearer C",{action:"link",studentId:"a",folder:"https://drive.google.com/file/d/passpasspass/view"});ok(r.s===400||r.s===404,"link to non-folder rejected "+r.s);
r=await call("Bearer C",{action:"purge",studentId:"b"});ok(r.s===400,"purge needs confirm");
r=await call("Bearer C",{action:"purge",studentId:"b",confirm:"УДАЛИТЬ"});ok(r.s===200&&files.FB.trashed&&students.b.folder===null,"purge trashes folder & unlinks");
r=await call("Bearer X",{action:"list"});ok(r.s===401,"bad token 401");
r=await H(new Request("https://fn/drive",{method:"OPTIONS"}));ok(r.status===200&&r.headers.get("access-control-allow-origin")==="*","CORS preflight");
ok(tokenCalls===1,"google token cached ("+tokenCalls+")");
console.log(fails?fails+" FAILED":"ALL PASSED");
