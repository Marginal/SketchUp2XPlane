var reText =/^[\w/]*$/;
var reInt  =/^\d*$/;
var reFloat=/^\-?\d*.?\d*$/;

function checkText(e)  { window.setTimeout(function() { checkAndSet(e, reText);  }, 0) }
function checkInt(e)   { window.setTimeout(function() { checkAndSet(e, reInt);   }, 0) }
function checkFloat(e) { window.setTimeout(function() { checkAndSet(e, reFloat); }, 0) }

function checkAndSet(e, re)
{
    if (re.test(e.value)) {
        e.style.background="White";
        window.location="skp:on_set_var@" + e.name
    } else {
        e.style.background="LightSalmon";
    }
}

function resetKeyframes()
{
    var keyframes=document.getElementById("keyframes");
    while (keyframes.rows.length) {
        keyframes.deleteRow(-1)
    }
    // CARPE.Sliders.objects[0].targets=[function() { window.location='skp:on_preview' }];	// Hack! Assumes only one slider on the page
}

function addInserter(keyframe)
{
    var keyframes=document.getElementById("keyframes");
    var row=keyframes.insertRow(-1)
    row.insertCell(-1).innerHTML='<input type="button" class="addremovebutton" value="+" onclick="window.location=\'skp:on_insert_frame@'+keyframe+'\'">'
}

function addKeyframe(keyframe, val, hasdeleter)
{
    var keyframes=document.getElementById("keyframes");
    var row=keyframes.insertRow(-1)
    if (hasdeleter) {
        row.insertCell(-1).innerHTML='<input type="button" class="addremovebutton" value="-" onclick="window.location=\'skp:on_delete_frame@'+keyframe+'\'">'
    } else {
        row.insertCell(-1).innerHTML='<input type="button" class="addremovebutton" value="-" disabled>'
    }
    row.insertCell(-1).innerHTML="Keyframe #"+keyframe
    row.insertCell(-1).innerHTML='<input type="text" name="frame'+keyframe+'" id="frame'+keyframe+'" value="'+val+'" size="8" onchange="checkFloat(this)" onkeyup="checkFloat(this)" oncut="checkFloat(this)" onpaste="checkFloat(this)">'
    row.insertCell(-1).innerHTML='<input type="button" value="Set Position" onclick="window.location=\'skp:on_set_position@'+keyframe+'\'">'
}

function addLoop(val)
{
    var keyframes=document.getElementById("keyframes");
    var row=keyframes.insertRow(-1)
    row.insertCell(-1)
    row.insertCell(-1).innerHTML="Loop"
    row.insertCell(-1).innerHTML='<input type="text" name="loop" id="loop" value="'+val+'" size="8" onchange="checkFloat(this)" onkeyup="checkFloat(this)" oncut="checkFloat(this)" onpaste="checkFloat(this)">'
}

function previewCallback(e)
{
    window.location='skp:on_preview@'+e.value/200
}
