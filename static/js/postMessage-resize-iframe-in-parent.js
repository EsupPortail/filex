// Version 1.0.0

var postMessage_resize_iframe_in_parent;
if (!postMessage_resize_iframe_in_parent) {
    postMessage_resize_iframe_in_parent = true;
  (function () {
    var resizedByUs = false;
    var previousHeight;

    var mylog = function() {};
    //if (window['console'] !== undefined) { mylog = function(s) { console.log(s); }; } 
    //else { mylog = function(s) { alert(s); }; }

    if (parent == window) return;

    var target = parent.postMessage ? parent : 
	(parent.document.postMessage ? parent.document : undefined);
    if (typeof target == "undefined") return;
    

////////////////////////////////////////////////////////////////////////////////
// below from shindig dynamic-size-util.js
////////////////////////////////////////////////////////////////////////////////
  /**
   * @private
   */
  function getElementComputedStyle(elem, attr) {
    if (window.getComputedStyle) {
      var style = window.getComputedStyle(elem, null);
    } else {
      var style = elem.currentStyle;
    }
    return attr && style ? style[attr] : style;
  }
  /**
   * Parse out the value (specified in px) for a CSS attribute of an element.
   *
   * @param {Element} elem the element with the attribute to look for.
   * @param {string} attr the CSS attribute name of interest.
   * @return {number} the value of the px attr of the elem, undefined if the attr was undefined.
   * @private
   */
  function parseIntFromElemPxAttribute(elem, attr) {
    var value = getElementComputedStyle(elem, attr);
    if (value) {
      value.match(/^([0-9]+)/);
      return parseInt(RegExp.$1, 10);
    }
  }
  /**
   * Get the height (truthy) or width (falsey)
   */
  var getDimen = function (height) {
    var result = 0;
    var queue = [document.body];

    while (queue.length > 0) {
      var elem = queue.shift();
      var children = elem.childNodes;

      /*
       * Here, we are checking if we are a container that clips its overflow with
       * a specific height, because if so, we should ignore children
       */

      // check that elem is actually an element, could be a text node otherwise
      if (typeof elem.style !== 'undefined' && elem !== document.body) {
        // Get the overflowY value, looking in the computed style if necessary
        var overflow = elem.style[height ? 'overflowY' : 'overflowX'];
        if (!overflow) {
          overflow = getElementComputedStyle(elem, height ? 'overflowY' : 'overflowX');
        }

        // The only non-clipping values of overflow is 'visible'. We assume that 'inherit'
        // is also non-clipping at the moment, but should we check this?
        if (overflow != 'visible' && overflow != 'inherit') {
          // Make sure this element explicitly specifies a height
          var size = elem.style[height ? 'height' : 'width'];
          if (!size) {
            size = getElementComputedStyle(elem, height ? 'height' : 'width');
          }
          if (size && size.length > 0 && size != 'auto') {
            // We can safely ignore the children of this element,
            // so move onto the next in the queue
            continue;
          }
        }
      }

      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (typeof child.style != 'undefined') {  // Don't measure text nodes
          var start = child.offsetTop,
              dimenEnd = 'marginBottom',
              size = child.offsetHeight,
              dir = getElementComputedStyle(child, 'direction');

          if (!height) {
            start = child.offsetLeft;
            dimenEnd = 'marginRight';
            size = child.offsetWidth;

            // compute offsetRight
            if (dir == 'rtl' && typeof start != 'undefined' && typeof size != 'undefined' && child.offsetParent) {
              start = child.offsetParent.offsetWidth - start - size;
            }
          }

          if (typeof start != 'undefined' && typeof size != 'undefined') {
            // offsetHeight already accounts for borderBottom, paddingBottom.
            var end = start + size + (parseIntFromElemPxAttribute(child, dimenEnd) || 0);
            result = Math.max(result, end);
          }
        }
        queue.push(child);
      }
    }

    // Add border, padding and margin of the containing body.
    return result +
        (parseIntFromElemPxAttribute(document.body, height ? 'borderBottom' : 'borderRight') || 0) +
        (parseIntFromElemPxAttribute(document.body, height ? 'marginBottom' : 'marginRight') || 0) +
        (parseIntFromElemPxAttribute(document.body, height ? 'paddingBottom' : 'paddingRight') || 0);
  };
////////////////////////////////////////////////////////////////////////////////


    var postMessageIframeHeight = function(kind) {

	var height = getDimen(true);
	var changed = height !== previousHeight;
	if (changed) 
	    mylog("heights changed: " + height + " (previousHeight:" + previousHeight + ") ")
	//else
	//    mylog("heights unchanged " + heights);

	if (kind !== "load" && !changed) {
	    // ignore
	    resizedByUs = false;
	} else if (kind === "windowResize" && resizedByUs && (height < previousHeight || window.resizeIframe_disableDangerousWindowResize)) {
	    mylog("new heights ignored")
	    resizedByUs = false;
	} else if (height > 20) {
            var horiz_scroll_height = 20;
            height += horiz_scroll_height;

	    mylog("sending height " + height);
	    target.postMessage("iframeHeight " + height, "*");
	    resizedByUs = true;
        }
	previousHeight = height;
    };

    var intervalId;
    var intervalCount = 0;

    var checkResize = function() {
        mylog("checkResize");
        intervalCount--;
        if (intervalCount == 0) {
           intervalId = clearInterval(intervalId);
        } else {
           postMessageIframeHeight("");
        }
    };

    var mayRegisterCheckResize = function() {
	mylog("mayRegisterCheckResize " + intervalId);
        if (!intervalId) {
           intervalId = setInterval(checkResize, 500);
        }
        intervalCount = Math.round((window.mayRegisterCheckResizeTime || 2) * 1000 / 500);
    }


    var load = function(e) {
        //mylog("load");
        postMessageIframeHeight("load");
	mayRegisterCheckResize();
    };

    var windowResize = function(e) {
        mylog("windowResize (resizedByUs:" + resizedByUs + ")");
	postMessageIframeHeight("windowResize");
    };

    var click = function () {
	mylog("click");
	mayRegisterCheckResize();
    };

    if (window.addEventListener){
	if (document.doctype) {
	    window.addEventListener("load", load, false);
	    window.addEventListener("resize", windowResize, false);
	    document.addEventListener("click", click, false);
	}
	else
	    mylog("postMessage-resize-iframe-in-parent: no DOCTYPE, aborting");
    } else {
	// for IE
	var ie_has_doctype = function() {
	    var doctype = document.childNodes[0];
	    return doctype && doctype.data && 
		typeof doctype.data === "string" && 
		doctype.data.indexOf("DOCTYPE ") === 0;
	};
	if (ie_has_doctype()) {
	    window.attachEvent("onload", load);
	    window.attachEvent("onresize", windowResize);
	    document.attachEvent("onclick", click);
	}
	else
	    mylog("postMessage-resize-iframe-in-parent: no DOCTYPE found, aborting");
    }

    var loadCSS = function (url) {
	var fileref = document.createElement("link");
	fileref.setAttribute("rel", "stylesheet");
	fileref.setAttribute("type", "text/css");
	fileref.setAttribute("href", url);
	document.getElementsByTagName("head")[0].appendChild(fileref);
    };
    if (window['cssToLoadIfInsideIframe']) 
	loadCSS(window['cssToLoadIfInsideIframe']);

    function xhrPing(url) {
         if (!window.XMLHttpRequest) return;
	 mylog("xhrPing " + url);
         var xhr = new XMLHttpRequest();
         xhr.open("GET", url, true);
         xhr.send(null);
    }

    function ping_to_increase_session_timeout(params) {
      var interval = params.app - 1;
      var nb = Math.ceil(params.wanted / interval) - 1;
      mylog("ping_to_increase_session_timeout: " + nb + " times every " + interval + " minutes");
      var id = setInterval(function() { 
	  xhrPing(window.location.href);
	  if (--nb == 0) clearInterval(id);
      }, interval * 60 * 1000);
    }

    var params = window.bandeau_ENT && window.bandeau_ENT.ping_to_increase_session_timeout;
    if (params) ping_to_increase_session_timeout(params);

  })();
}