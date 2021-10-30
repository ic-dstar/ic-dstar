var countDownTime = {
	init: function(a, b, c, d, e) {
		this.t = a, this.d = b, this.h = c, this.m = d, this.s = e
	},
	start: function() {
		var a = this;
		$('.tlayer').fadeIn(150);
		$('#countdown').show();
		setInterval(a.timer, 1e3);
	},
	timer: function(a) {
		var b, c, d, e, f, g, h;
		a = this.countDownTime, b = new Date, c = new Date(a.t), d = c.getTime() - b.getTime(), e = Math.floor(a.formatTime(d, "day")), f = Math.floor(a.formatTime(d, "hours")), g = Math.floor(a.formatTime(d, "minutes")), h = Math.floor(a.formatTime(d, "seconds")), a.d && (a.d.innerText = a.formatNumber(e)), a.h && (a.h.innerText = a.formatNumber(f)), a.m && (a.m.innerText = a.formatNumber(g)), a.s && (a.s.innerText = a.formatNumber(h))
		//console.log(a.d.innerText + a.h.innerText + a.m.innerText + a.s.innerText);
		var dd = e + f + g + h;
		if(dd<=0){
			$('.tlayer').fadeOut(150);
			$('#countdown').hide();
		}
	},
	formatNumber: function(a) {
		if(a<=0){a=0}
		return a = a.toString(), a[1] ? a : "0" + a
	},
	formatTime: function(a, b) {
		switch (b) {
			case "day":
				return a / 1e3 / 60 / 60 / 24;
			case "hours":
				return a / 1e3 / 60 / 60 % 24;
			case "minutes":
				return a / 1e3 / 60 % 60;
			case "seconds":
				return a / 1e3 % 60
		}
	}
};