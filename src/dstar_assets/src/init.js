import Pagination from "tui-pagination";

export const dstarjs = {
  txlist: [],
  iilist: [],
  user: "",
  userstar: 0.0,
  airdrop: false,
  connect_handler: null,
  search_handler: null,
  buy_handler: null,
  refresh_handler: null,
  page: 1,
  pagesize: 24,
  pager: null,
  default_opt: {},
  lockTimer: null,
  loadingList: false,
  loadingTx: false,

  init(ccb, scb, bcb, recb) {
    this.connect_handler = ccb;
    this.search_handler = scb;
    this.buy_handler = bcb;
    this.refresh_handler = recb;

    this._init_page();
    this._init_search();

    var self = this;
    this.lockTimer = setInterval(() => {
      self.lockShowTimeII();
    }, 1000);
  },

  isauth() {
    return this.user != "";
  },

  setuser(user) {
    this.user = user;
    if (!this.isauth()) {
      $("#order").hide();
    } else {
      let str = this.user;
      $("#order").html(str.substr(0, 11) + "..." + str.substr(-8) + '<i class="down"></i>');
      $("#plugconnect").hide();
      $("#order").show();
    }
  },

  getII(id) {
    for (var i = 0; i < this.iilist.length; i++) {
      if (this.iilist[i].id == id) {
        return this.iilist[i];
      }
    }
    return null;
  },

  loading(clear) {
    if (clear) {
      $("#ii-item-list").html("");
    }
    $("#ii-loading").show();
    this.loadingList = true;
  },

  lockShowTimeII() {
    var self = this;
    for (var i = 0; i < this.iilist.length; i++) {
      if (this.iilist[i].locked) {
        this.iilist[i].lockSecond -= 1;
        if (this.iilist[i].lockSecond < 0) {
          this.iilist[i].lockSecond = 0;
        }
        let id = Number(this.iilist[i].id);
        let second = this.iilist[i].lockSecond + "";
        $(`#ii-item-${id} .showtimes`).html(second);
        if (this.iilist[i].lockSecond <= 0 && $(`#ii-item-${id} .locked`).length > 0) {
          setTimeout(() => {
            $(`#ii-item-${id}`).append(`<div class="buy" data="${id}"> BUY </div>`);
            $(`#ii-item-${id} .locked`).remove();
            $(`#ii-item-${id} .lockbtn`).remove();
            self._re_buy();
          }, 150);
        }
      }
    }
  },

  refreshII(opt = {}) {
    var self = this;
    if (self.loadingList) {
      return;
    }
    self.loading(true);
    let id = parseInt($(".searchfld .input").val());
    let myopt = {
      airdrop: self.airdrop,
      id: id ? id : 0,
      page: self.page,
      size: self.pagesize,
      highId: 0,
      lowId: 0,
      lowScore: 0,
      highScore: 0,
      itype: [],
      ssort: [],
      psort: [],
    };
    if (!myopt.id) {
      let highId = parseInt($("#sinput-high").val());
      let lowId = parseInt($("#sinput-low").val());
      myopt.highId = highId ? highId : 0;
      myopt.lowId = lowId ? lowId : 0;
    }
    opt = { ...myopt, ...opt };
    if (self.search_handler) {
      // console.log(opt);
      self.default_opt = opt;
      self.search_handler(opt);
    }
  },

  renderII(total, lists) {
    $("#ii-loading").hide();
    $("#ii-item-tmpl").tmpl(lists).appendTo("#ii-item-list");
    let total_str = total.toLocaleString();
    $(".searchfld input").attr("placeholder", `${total_str} results, Please Input II Number`);

    this._re_buy();

    this.iilist = lists;
    this.loadingList = false;
    if (this.pager) {
      this.pager.setTotalItems(Number(total));
      this.pager._paginate(this.page);
    }
  },

  lockII(id) {
    for (var i = 0; i < this.iilist.length; i++) {
      if (this.iilist[i].id == id) {
        this.iilist[i].locked = true;
        this.iilist[i].lockTime = BigInt(new Date().getTime()) * BigInt(1e6);
        this.iilist[i].lockSecond = 150;
      }
    }
    $(`#ii-item-${id} .buy`).remove();
    $(`#ii-item-${id}`).append(`<div class="locked"></div><div class="lockbtn"><span class="showtimes">150</span>S Unlock</div>`);
    $(".cancel").click();
  },

  renderStar(star) {
    this.userstar = star;
    $("#ii-user-star").html("" + this.userstar);
  },

  renderTx(lists) {
    var self = this;
    self.loadingTx = false;
    $(".orderfld .loading").hide();
    if (lists.length <= 0) {
      return;
    }

    $("#ii-tx-count").html("" + lists.length);
    self.txlist = lists;
    $("#ii-order-list").html("");
    $("#ii-record-tmpl").tmpl(lists).appendTo("#ii-order-list");
    self._re_seed();
  },

  renderTxErr() {
    var self = this;
    self.loadingTx = false;
    $(".orderfld .loading").hide();
    if (lists.length <= 0) {
      return;
    }

    $("#ii-order-list").html("<tr><td colspan='6'>load error, please click the refresh again! </td></tr>");
  },

  paying(status) {
    var self = this;
    if (status == 1) {
      $("#paying").fadeIn(150);
      $("#paying span").html("please wait, locking......");
      self.popup(true);
    } else if (status == 2) {
      $("#paying").fadeIn(150);
      $("#paying span").html("please wait, paying......");
      self.popup(true);
    } else if (status == 3) {
      $("#paying").hide();
      $("#complete").fadeIn(150);
      self.popup(true);
    } else {
      $("#complete").hide();
      $("#paying").hide();
      self.popup(false);
    }
  },

  popup(show) {
    if (show) {
      $(".tlayer").show();
      $("body").css({ "overflow-x": "hidden", "overflow-y": "hidden" });
    } else {
      $(".tlayer").hide();
      $("body").css({ "overflow-x": "auto", "overflow-y": "auto" });
    }
  },

  _re_buy() {
    var self = this;
    $(".buy")
      .off("click")
      .click(function () {
        if (!self.isauth()) {
          if (!window.ic || !window.ic.plug) {
            window.open("https://plugwallet.ooo/", "_blank");
          } else {
            $("#plugconnect").click();
          }
          return;
        }
        let id = parseInt($(this).attr("data"));
        let ii = self.getII(id);
        if (!ii) {
          return;
        }
        if (ii.limitStar > 0 && self.userstar < ii.limitStar) {
          alert("You are not allowed to buy it!");
          return;
        }

        self.popup(true);
        $("#buyon").attr("data", $(this).attr("data"));
        $("#buyon").fadeIn(150);
      });
  },

  _re_seed() {
    var self = this;
    $(".seed").click(function () {
      var that = $(this);
      var thenext = that.parent().parent().next(".phrase");
      if (that.text() == "show") {
        that.text("hide");
        thenext.show();
        thenext.siblings(".phrase").hide();
        that.parent().parent().siblings(".noborder").children().find(".seed").text("show");
      } else {
        that.text("show");
        thenext.hide();
      }
    });
    if (typeof Clipboard != "function") {
      return;
    }
    let clipboard = new Clipboard(".copy");
    clipboard.on("success", function (e) {
      console.log("copy success");
      $("#copyok").show(220);
      // self.popup(true);
    });
  },

  _init_search() {
    var self = this;
    self.pager = new Pagination($("#ii-page-root"), {
      totalItems: 0,
      itemsPerPage: self.pagesize,
      visiblePages: 8,
      centerAlign: true,
    });
    self.pager.on("beforeMove", function (eventData) {
      return true;
    });
    self.pager.on("afterMove", function (eventData) {
      if (self.page == eventData.page) {
        return;
      }
      self.page = eventData.page;
      self.refreshII({ ...self.default_opt, ...{ page: self.page } });
    });

    $(".searchfld .sbtn, .fliter .go").click(function () {
      if (self.search_handler) {
        self.page = 1;
        self.refreshII();
      }
    });

    $("#airdrop-select").click(function () {
      self.airdrop = true;
      self.page = 1;
      self.refreshII({});
    });

    $("#all-select").click(function () {
      self.airdrop = false;
      self.page = 1;
      self.refreshII({});
    });

    $("#itype-select ul li a").click(function () {
      console.log("itype select");
      let itype = $(this).attr("data");
      self.refreshII({
        itype: [{ [itype]: null }],
      });
    });

    $("#score-select ul li a").click(function () {
      console.log("score select");
      let min = $(this).attr("min");
      let max = $(this).attr("max");
      self.refreshII({
        lowScore: parseInt(min),
        highScore: parseInt(max),
      });
    });

    $("#price-sort ul li a").click(function () {
      console.log("price sort");
      let sort = $(this).attr("data");
      self.refreshII({
        psort: [{ [sort]: null }],
      });
    });

    $("#size-sort ul li a").click(function () {
      console.log("size sort");
      let sort = $(this).attr("data");
      self.refreshII({
        ssort: [{ [sort]: null }],
      });
    });
  },

  _init_page() {
    var self = this;
    $(".item").hover(
      function () {
        $(this).addClass("up");
        $(this).children("ul").slideDown(180);
      },
      function () {
        $(this).removeClass("up");
        $(this).children("ul").slideUp(180);
      }
    );

    var status = 1;
    $("#order").click(function () {
      if (status == 1) {
        let px = "85px";
        if ($("#tip").is(":visible")) {
          px = "123px";
        }
        $(".layer").show();
        $(".orderfld").slideDown();
        $(".orderfld, .layer").css("top", px);
        $(this).children("i").removeClass("down");
        $(this).children("i").addClass("up");
        status = 0;
        $("body").css({
          "overflow-x": "hidden",
          "overflow-y": "hidden",
        });
      } else {
        $(".orderfld").slideUp();
        $(".layer").hide();
        $(this).children("i").removeClass("up");
        $(this).children("i").addClass("down");
        status = 1;
        $("body").css({
          "overflow-x": "auto",
          "overflow-y": "auto",
        });
      }
    });
    $(".layer").click(function () {
      $(".orderfld").slideUp();
      $(".layer").hide();
      $("#order").children("i").removeClass("up");
      $("#order").children("i").addClass("down");
      $("body").css({ "overflow-x": "auto", "overflow-y": "auto" });
      status = 1;
    });

    $(".delete").click(function () {
      $("#del").show(220);
      self.popup(true);
    });
    $(".cancel").click(function () {
      self.popup(false);
      $("#buyon").hide();
      $("label").each(function () {
        var that = $(this);
        if (that.hasClass("radio-on")) {
          that.removeClass("radio-on");
          that.addClass("radio-off");
          that.children(":input").val("0");
        }
      });
      $("#continue").addClass("disabled");
    });
    $("label").click(function () {
      var that = $(this);
      if (that.hasClass("radio-off")) {
        that.removeClass("radio-off");
        that.addClass("radio-on");
        that.children(":input").val("1");
      } else {
        that.addClass("radio-off");
        that.removeClass("radio-on");
        that.children(":input").val("0");
      }
      var conval = "";
      $(":input[name=condition]").each(function () {
        conval += $(this).val();
      });
      if (conval == "111") {
        $("#continue").removeClass("disabled");
      } else {
        $("#continue").addClass("disabled");
      }
    });
    $("#continue").click(function () {
      var that = $(this);
      if (that.hasClass("disabled")) {
        alert("Please check the box first.");
        return;
      }
      $("#buyon").hide();
      self.popup(false);
      let buyid = parseInt($("#buyon").attr("data"));
      if (buyid && self.buy_handler) {
        self.paying(1);
        self.buy_handler(buyid);
      }
    });
    $(".sure").click(function () {
      self.popup(false);
      $("#copyok").hide();
    });
    $("#close, #complete").click(function () {
      $("#complete").fadeOut(150);
      self.popup(false);
    });
    $(".closetip").click(function () {
      $("#tip").hide(150);
    });

    $("#refresh").click(function () {
      if (self.loadingTx) {
        return;
      }
      self.loadingTx = true;
      $("#ii-order-list").html("");
      $(".orderfld .loading").show();
      if (self.refresh_handler) {
        self.refresh_handler();
      }
    });

    $("#plugconnect").click(async function () {
      if (!window.ic || !window.ic.plug) {
        window.open("https://plugwallet.ooo/", "_blank");
        return;
      }
      $(this).html('Connecting<span class="dot"></span>');
      self.popup(true);
      if (self.connect_handler) {
        let res = await self.connect_handler();
        if (!res) {
          $(this).html("connect to Plug");
        }
      }
      self.popup(false);
    });
  },
};

export const countDownTime = {
  init: function (a) {
    this.t = a;
  },
  start: function () {
    var a = this;
    $(".tlayer").fadeIn(150);
    $("#countdown").show();
    setInterval(() => {
      a.timer();
    }, 1e3);
  },
  timer: function () {
    var a = this;
    var b, c, d, e, f, g, h;
    (b = new Date()),
      (c = new Date(a.t)),
      (d = c.getTime() - b.getTime()),
      (e = Math.floor(a.formatTime(d, "day"))),
      (f = Math.floor(a.formatTime(d, "hours"))),
      (g = Math.floor(a.formatTime(d, "minutes"))),
      (h = Math.floor(a.formatTime(d, "seconds")));
    //console.log(a.d.innerText + a.h.innerText + a.m.innerText + a.s.innerText);
    var dd = e + f + g + h;
    if (dd <= 0) {
      $(".tlayer").fadeOut(150);
      $("#countdown").hide();
      window.location.reload();
    }
  },
  formatNumber: function (a) {
    if (a <= 0) {
      a = 0;
    }
    return (a = a.toString()), a[1] ? a : "0" + a;
  },
  formatTime: function (a, b) {
    switch (b) {
      case "day":
        return a / 1e3 / 60 / 60 / 24;
      case "hours":
        return (a / 1e3 / 60 / 60) % 24;
      case "minutes":
        return (a / 1e3 / 60) % 60;
      case "seconds":
        return (a / 1e3) % 60;
    }
  },
};
