const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// Put your actual internal execution script code here!
const luaSource = `print("Your script loaded successfully!")
script_key = "YOUR_SECRET_KEY_HERE"; 
loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/cc815ef92aaf3ed41a37aa4d87cd93ff.lua"))()`;

const htmlTemplate = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Lua Script Loader</title>
    <style>
        :root{--bg:#1a1e30;--fg:#fff;--muted:#d1d1d1;--pane:#121626;--pane2:#0f1322;--kw:#569cd6;--str:#ce9178;--com:#6a9955;--num:#b5cea8}
        *{box-sizing:border-box}
        body{margin:0;font-family:Roboto,Arial,sans-serif;background-color:var(--bg);color:var(--fg);display:flex;align-items:center;justify-content:center;min-height:100vh}
        .container{text-align:center;padding:20px;background:rgba(255,255,255,0);border-radius:12px;box-shadow:0 8px 15px transparent;width:min(900px,92vw)}
        h1{font-size:22px;margin:0 0 10px}
        p{font-size:14px;color:var(--muted);margin:6px 0 16px}
        .editor{position:relative;text-align:left;border-radius:10px;background:linear-gradient(180deg,var(--pane),var(--pane2));padding:14px 44px 14px 14px;overflow:auto;box-shadow:inset 0 0 0 1px rgba(255,255,255,.06)}
        pre{margin:0;white-space:pre;overflow:auto}
        code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:14px;line-height:1.5}
        .kw{color:var(--kw);font-weight:600}
        .str{color:var(--str)}
        .com{color:var(--com);font-style:italic}
        .num{color:var(--num)}
        .copy{position:absolute;top:8px;right:8px;border:0;border-radius:8px;background:#2a3150;color:#fff;padding:6px 10px;font-size:12px;cursor:pointer;user-select:none;transition:transform .05s ease,opacity .2s ease}
        .copy:active{transform:scale(.97)}
        @media (min-width:640px){h1{font-size:24px}p{font-size:15px}code{font-size:15px}}
    </style>
</head>
<body>
    <div class="container">
        <h1>📜 Loadstring</h1>
        <p>Contents cannot be displayed raw on browser.</p>
        <div class="editor">
            <button class="copy">Copy</button>
            <pre><code id="code"></code></pre>
        </div>
    </div>
    <script>
        const luaSource = \`${luaSource.replace(/`/g, '\\`').replace(/\${/g, '\\${')}\`;
        function escapeHTML(e){return e.replace(/[&<>]/g,e=>({"&":"&amp;","<":"&lt;",">":"&gt;"})[e])}
        function highlightLua(e){
            let t=escapeHTML(e),n=/"(?:\.|[^"\\])*"|'/g,a=[],l=0,c;
            for(;c=n.exec(t);)c.index>l&&a.push({t:"code",v:t.slice(l,c.index)}),a.push({t:"str",v:c[0]}),l=n.lastIndex;
            l<t.length&&a.push({t:"code",v:t.slice(l)});
            let s=/\\b(local|function|end|if|then|else|elseif|for|while|repeat|until|return|not|and|or|do|in|true|false|nil)\\b/g,r=/\\b(loadstring|game|HttpGet)\\b/g,i=/\\b(\\d+(?:\\.\\d+)?)\\b/g;
            function o(e){return e.replace(i,"<span class=num>$1</span>").replace(s,"<span class=kw>$1</span>").replace(r,"<span class=kw>$1</span>")}
            return a.map(e=>{var t;return"str"===e.t?"<span class=str>"+e.v+"</span>":(t=e.v).split("\\n").map(e=>{let t=e.indexOf("--");if(-1===t)return o(e);let n=o(e.slice(0,t)),a=e.slice(t);return n+"<span class=com>"+a+"</span>"}).join("\\n")}).join("")
        }
        const codeEl=document.getElementById("code");
        codeEl.innerHTML=highlightLua(luaSource);
        function flash(e){let t=document.querySelector(".copy"),n=t.textContent;t.textContent=e,setTimeout(()=>t.textContent=n,900)}
        document.querySelector(".copy").addEventListener("click",async()=>{
            try{await navigator.clipboard.writeText(luaSource),flash("Copied!")}catch{
                let e=document.createElement("textarea");e.value=luaSource;document.body.appendChild(e);e.select();
                try{document.execCommand("copy"),flash("Copied!")}catch{}e.remove()
            }
        });
    </script>
</body>
</html>`;

app.get('/script.lua', (req, res) => {
    const userAgent = req.headers['user-agent'] || '';
    
    // Identifies executor tools vs default web browsers
    const isRoblox = userAgent.toLowerCase().includes('roblox') || userAgent.toLowerCase().includes('headers');

    if (isRoblox) {
        res.setHeader('Content-Type', 'text/plain');
        return res.send(luaSource);
    } else {
        res.setHeader('Content-Type', 'text/html');
        return res.send(htmlTemplate);
    }
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
