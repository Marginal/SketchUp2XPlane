var reText =/^[\w/]*$/;
var reInt  =/^\d*$/;
var reFloat=/^\-?\d*.?\d*$/;

// Must be consistent with SU2XPlane.rb
var ANIM_DATAREF='dataref'
var ANIM_INDEX='index'
var ANIM_FRAME_='frame_'
var ANIM_MATRIX_='matrix_'
var ANIM_LOOP='loop'
var ANIM_HS_='hs_'
var ANIM_VAL_HIDE='hide'
var ANIM_VAL_SHOW='show'
var ANIM_HS_HIDESHOW='_hideshow'
var ANIM_HS_DATAREF='_dataref'
var ANIM_HS_INDEX='_index'
var ANIM_HS_FROM='_from'
var ANIM_HS_TO='_to'

function checkText(e)  { window.setTimeout(function() { checkAndSet(e, reText);  }, 0) }
function checkInt(e)   { window.setTimeout(function() { checkAndSet(e, reInt);   }, 0) }
function checkFloat(e) { window.setTimeout(function() { checkAndSet(e, reFloat); }, 0) }

function checkAndSet(e, re)
{
    if (re.test(e.value)) {
        e.style.background="White";
        window.location="skp:on_set_var@" + e.id
    } else {
        e.style.background="LightSalmon";
    }
}

function resetDialog(title, dataref, index, l10n_datarefval, l10n_position, l10n_preview, l10n_hideshow, l10n_erase)
{
    document.getElementById("title").innerHTML=title;
    document.getElementById(ANIM_DATAREF).value=dataref;
    document.getElementById(ANIM_INDEX).value=index;
    document.getElementById("datarefval").innerHTML=l10n_datarefval;
    document.getElementById("position").innerHTML=l10n_position;
    document.getElementById("preview").innerHTML=l10n_preview;
    document.getElementById("hideshowtitle").innerHTML=l10n_hideshow;
    document.getElementById("erase").value=l10n_erase;

    var keyframes=document.getElementById("keyframes");
    while (keyframes.rows.length) {
        keyframes.deleteRow(-1)
    }

    var hideshow=document.getElementById("hideshow");
    while (hideshow.rows.length) {
        hideshow.deleteRow(-1)
    }

    inputs=document.getElementsByTagName("input")
    for (var i=0; i<inputs.length; i++) { inputs[i].disabled=false; }
}

function disable(disable_all, disable_preview)
{
    inputs=document.getElementsByTagName("input")
    for (var i=0; i<inputs.length; i++) { inputs[i].disabled|=disable_all; }
    document.getElementById('preview-slider').disabled=disable_preview
    disable_preview ? fdSlider.disable('preview-slider') : fdSlider.enable('preview-slider');
    document.body.style.backgroundColor=(disable_all ? "#bfdfb7" : "white");
}

function addFrameInserter(keyframe)
{
    var table=document.getElementById("keyframes");
    var row=table.insertRow(-1)
    row.insertCell(-1).innerHTML='<input type="button" class="addremovebutton" value="+" onclick="window.location=\'skp:on_insert_frame@'+keyframe+'\'">'
}

function addKeyframe(keyframe, val, hasdeleter, l10n_set, l10n_recall)
{
    var table=document.getElementById("keyframes");
    var row=table.insertRow(-1)
    if (hasdeleter) {
        row.insertCell(-1).innerHTML='<input type="button" class="addremovebutton" value="\u2212" onclick="window.location=\'skp:on_delete_frame@'+keyframe+'\'">'
    } else {
        row.insertCell(-1).innerHTML='<input type="button" class="addremovebutton" value="\u2212" disabled>'
    }
    row.insertCell(-1).innerHTML="Keyframe #"+keyframe
    row.insertCell(-1).innerHTML='<input type="text" id="'+ANIM_FRAME_+keyframe+'" value="'+val+'" size="6" onchange="checkFloat(this)" onkeyup="checkFloat(this)" oncut="checkFloat(this)" onpaste="checkFloat(this)">'
    row.insertCell(-1).innerHTML='<input type="button" value="'+l10n_set+'" onclick="window.location=\'skp:on_set_transform@'+keyframe+'\'"> <input type="button" value="'+l10n_recall+'" onclick="window.location=\'skp:on_get_transform@'+keyframe+'\'">'
}

function addLoop(val)
{
    var keyframes=document.getElementById("keyframes");
    var row=keyframes.insertRow(-1)
    cell=row.insertCell(-1)
    cell.innerHTML='DataRef'
    cell.style.visibility='hidden'	// So that input boxes line up with dataref input boxes
    row.insertCell(-1).innerHTML="Loop"
    row.insertCell(-1).innerHTML='<input type="text" id="'+ANIM_LOOP+'" value="'+val+'" size="6" onchange="checkFloat(this)" onkeyup="checkFloat(this)" oncut="checkFloat(this)" onpaste="checkFloat(this)">'
}

function addHSInserter(number)
{
    var table=document.getElementById("hideshow");
    var row=table.insertRow(-1)
    row.insertCell(-1).innerHTML='<input type="button" class="addremovebutton" value="+" onclick="window.location=\'skp:on_insert_hideshow@'+number+'\'">'
}

function addHideShow(number, hideshow, dataref, index, from, to, l10n_hide, l10n_show, l10n_when, l10n_to)
{
    var prefix=ANIM_HS_+number
    var table=document.getElementById("hideshow");
    var row=table.insertRow(-1)
    row.insertCell(-1).innerHTML='<input type="button" class="addremovebutton" value="\u2212" onclick="window.location=\'skp:on_delete_hideshow@'+number+'\'">'
    row.insertCell(-1).innerHTML='<input type="text" id="'+prefix+ANIM_HS_DATAREF+'" value="'+dataref+'" style="width: 200px;" onchange="checkText(this)" onkeyup="checkText(this)" oncut="checkText(this)" onpaste="checkText(this)"> [<input type="text" id="'+prefix+ANIM_HS_INDEX+'" value="'+index+'" size="3" onchange="checkInt(this)" onkeyup="checkInt(this)" oncut="checkInt(this)" onpaste="checkInt(this)">]'
    row=table.insertRow(-1)
    cell=row.insertCell(-1)
    cell.innerHTML='DataRef'
    cell.style.visibility='hidden'	// So that hideshow dataref and index input boxes line up with animation input boxes
    row.insertCell(-1).innerHTML='<select id="'+prefix+ANIM_HS_HIDESHOW+'" onchange="checkText(this)"> <option value="'+ANIM_VAL_HIDE+'">'+l10n_hide+'</option> <option value="'+ANIM_VAL_SHOW+'">'+l10n_show+'</option> </select> '+l10n_when+' <input type="text" id="'+prefix+ANIM_HS_FROM+'" value="'+from+'" size="6" onchange="checkFloat(this)" onkeyup="checkFloat(this)" oncut="checkFloat(this)" onpaste="checkFloat(this)"> '+l10n_to+' <input type="text" id="'+prefix+ANIM_HS_TO+'" value="'+to+'" size="6" onchange="checkFloat(this)" onkeyup="checkFloat(this)" oncut="checkFloat(this)" onpaste="checkFloat(this)">'
    document.getElementById(prefix+ANIM_HS_HIDESHOW).selectedIndex = (hideshow==ANIM_VAL_HIDE ? 0 : 1)
}

function previewCallback(e)
{
    window.location='skp:on_preview@'+e.value/200
}
