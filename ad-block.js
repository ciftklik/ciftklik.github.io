(function(window) {
var KillAdBlock = function(options) {
this._options = {
checkOnLoad:        false,
resetOnEnd:         false,
loopCheckTime:      50,
loopMaxNumber:      5,
baitClass:          &#39;pub_300x250 pub_300x250m pub_728x90 text-ad textAd text_ad text_ads text-ads text-ad-links&#39;,
baitStyle:          &#39;width: 1px !important; height: 1px !important; position: absolute !important; left: -10000px !important; top: -1000px !important;&#39;,
debug:              false
};
this._var = {
version:            &#39;1.2.0&#39;,
bait:               null,
checking:           false,
loop:               null,
loopNumber:         0,
event:              { detected: [], notDetected: [] }
};
if(options !== undefined) {
this.setOption(options);
}
var self = this;
var eventCallback = function() {
setTimeout(function() {
if(self._options.checkOnLoad === true) {
if(self._options.debug === true) {
self._log(&#39;onload-&gt;eventCallback&#39;, &#39;A check loading is launched&#39;);
}
if(self._var.bait === null) {
self._creatBait();
}
setTimeout(function() {
self.check();
}, 1);
}
}, 1);
};
if(window.addEventListener !== undefined) {
window.addEventListener(&#39;load&#39;, eventCallback, false);
} else {
window.attachEvent(&#39;onload&#39;, eventCallback);
}
};
KillAdBlock.prototype._options = null;
KillAdBlock.prototype._var = null;
KillAdBlock.prototype._bait = null;
KillAdBlock.prototype._log = function(method, message) {
console.log(&#39;[KillAdBlock][&#39;+method+&#39;] &#39;+message);
};
KillAdBlock.prototype.setOption = function(options, value) {
if(value !== undefined) {
var key = options;
options = {};
options[key] = value;
}
for(var option in options) {
this._options[option] = options[option];
if(this._options.debug === true) {
this._log(&#39;setOption&#39;, &#39;The option &quot;&#39;+option+&#39;&quot; he was assigned to &quot;&#39;+options[option]+&#39;&quot;&#39;);
}
}
return this;
};
KillAdBlock.prototype._creatBait = function() {
var bait = document.createElement(&#39;div&#39;);
bait.setAttribute(&#39;class&#39;, this._options.baitClass);
bait.setAttribute(&#39;style&#39;, this._options.baitStyle);
this._var.bait = window.document.body.appendChild(bait);
this._var.bait.offsetParent;
this._var.bait.offsetHeight;
this._var.bait.offsetLeft;
this._var.bait.offsetTop;
this._var.bait.offsetWidth;
this._var.bait.clientHeight;
this._var.bait.clientWidth;
if(this._options.debug === true) {
this._log(&#39;_creatBait&#39;, &#39;Bait has been created&#39;);
}
};
KillAdBlock.prototype._destroyBait = function() {
window.document.body.removeChild(this._var.bait);
this._var.bait = null;
if(this._options.debug === true) {
this._log(&#39;_destroyBait&#39;, &#39;Bait has been removed&#39;);
}
};
KillAdBlock.prototype.check = function(loop) {
if(loop === undefined) {
loop = true;
}
if(this._options.debug === true) {
this._log(&#39;check&#39;, &#39;An audit was requested &#39;+(loop===true?&#39;with a&#39;:&#39;without&#39;)+&#39; loop&#39;);
}
if(this._var.checking === true) {
if(this._options.debug === true) {
this._log(&#39;check&#39;, &#39;A check was canceled because there is already an ongoing&#39;);
}
return false;
}
this._var.checking = true;
if(this._var.bait === null) {
this._creatBait();
}
var self = this;
this._var.loopNumber = 0;
if(loop === true) {
this._var.loop = setInterval(function() {
self._checkBait(loop);
}, this._options.loopCheckTime);
}
setTimeout(function() {
self._checkBait(loop);
}, 1);
if(this._options.debug === true) {
this._log(&#39;check&#39;, &#39;A check is in progress ...&#39;);
}
return true;
};
KillAdBlock.prototype._checkBait = function(loop) {
var detected = false;
if(this._var.bait === null) {
this._creatBait();
}
if(window.document.body.getAttribute(&#39;abp&#39;) !== null
|| this._var.bait.offsetParent === null
|| this._var.bait.offsetHeight == 0
|| this._var.bait.offsetLeft == 0
|| this._var.bait.offsetTop == 0
|| this._var.bait.offsetWidth == 0
|| this._var.bait.clientHeight == 0
|| this._var.bait.clientWidth == 0) {
detected = true;
}
if(window.getComputedStyle !== undefined) {
var baitTemp = window.getComputedStyle(this._var.bait, null);
if(baitTemp.getPropertyValue(&#39;display&#39;) == &#39;none&#39;
|| baitTemp.getPropertyValue(&#39;visibility&#39;) == &#39;hidden&#39;) {
detected = true;
}
}
if(this._options.debug === true) {
this._log(&#39;_checkBait&#39;, &#39;A check (&#39;+(this._var.loopNumber+1)+&#39;/&#39;+this._options.loopMaxNumber+&#39; ~&#39;+(1+this._var.loopNumber*this._options.loopCheckTime)+&#39;ms) was conducted and detection is &#39;+(detected===true?&#39;positive&#39;:&#39;negative&#39;));
}
if(loop === true) {
this._var.loopNumber++;
if(this._var.loopNumber &gt;= this._options.loopMaxNumber) {
this._stopLoop();
}
}
if(detected === true) {
this._stopLoop();
this._destroyBait();
this.emitEvent(true);
if(loop === true) {
this._var.checking = false;
}
} else if(this._var.loop === null || loop === false) {
this._destroyBait();
this.emitEvent(false);
if(loop === true) {
this._var.checking = false;
}
}
};
KillAdBlock.prototype._stopLoop = function(detected) {
clearInterval(this._var.loop);
this._var.loop = null;
this._var.loopNumber = 0;
if(this._options.debug === true) {
this._log(&#39;_stopLoop&#39;, &#39;A loop has been stopped&#39;);
}
};
KillAdBlock.prototype.emitEvent = function(detected) {
if(this._options.debug === true) {
this._log(&#39;emitEvent&#39;, &#39;An event with a &#39;+(detected===true?&#39;positive&#39;:&#39;negative&#39;)+&#39; detection was called&#39;);
}
var fns = this._var.event[(detected===true?&#39;detected&#39;:&#39;notDetected&#39;)];
for(var i in fns) {
if(this._options.debug === true) {
this._log(&#39;emitEvent&#39;, &#39;Call function &#39;+(parseInt(i)+1)+&#39;/&#39;+fns.length);
}
if(fns.hasOwnProperty(i)) {
fns[i]();
}
}
if(this._options.resetOnEnd === true) {
this.clearEvent();
}
return this;
};
KillAdBlock.prototype.clearEvent = function() {
this._var.event.detected = [];
this._var.event.notDetected = [];
if(this._options.debug === true) {
this._log(&#39;clearEvent&#39;, &#39;The event list has been cleared&#39;);
}
};
KillAdBlock.prototype.on = function(detected, fn) {
this._var.event[(detected===true?&#39;detected&#39;:&#39;notDetected&#39;)].push(fn);
if(this._options.debug === true) {
this._log(&#39;on&#39;, &#39;A type of event &quot;&#39;+(detected===true?&#39;detected&#39;:&#39;notDetected&#39;)+&#39;&quot; was added&#39;);
}
return this;
};
KillAdBlock.prototype.onDetected = function(fn) {
return this.on(true, fn);
};
KillAdBlock.prototype.onNotDetected = function(fn) {
return this.on(false, fn);
};
window.KillAdBlock = KillAdBlock;
if(window.killAdBlock === undefined) {
window.killAdBlock = new KillAdBlock({
checkOnLoad: true,
resetOnEnd: true
});
}
})(window);
function show_message()
{
kill_adBlock_message_delay = kill_adBlock_message_delay * 1000;
kill_adBlock_close_automatically_delay = kill_adBlock_close_automatically_delay * 1000;
setTimeout(function(){
jQuery(&#39;.kac486&#39;).html(kill_adBlock_message);
jQuery(&#39;.kac486-container&#39;).fadeIn();
}, kill_adBlock_message_delay);
if(kill_adBlock_close_automatically_delay&gt;0 &amp;&amp; kill_adBlock_close_automatically==1)
{
setTimeout(function(){
jQuery(&#39;.close-btn&#39;).trigger(&#39;click&#39;);
}, kill_adBlock_close_automatically_delay);
}
}
function adBlockNotDetected(){}
jQuery(document).ready(function(){
jQuery(&#39;.close-btn&#39;).click(function(){
jQuery(&#39;.kac486-container&#39;).fadeOut(&#39;kac486-hide&#39;);
});
});
var kill_adBlock_status = 1;
var kill_adBlock_message = &#39;Adblock eklentisini desteklemiyoruz. Lüften devre dışı bırakınız..&#39;;
var kill_adBlock_message_delay = 0;
var kill_adBlock_close_btn = 0;
var kill_adBlock_close_automatically = 0;
var kill_adBlock_close_automatically_delay = 0;
var kill_adBlock_message_type = 2;
function adBlockDetected() {
show_message();
}
if(typeof killAdBlock === &#39;undefined&#39;) {
adBlockDetected();
} else {
killAdBlock.onDetected(adBlockDetected).onNotDetected(adBlockNotDetected);
}
