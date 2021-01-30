
merge = Array.prototype.concat

$(document).on 'templateinit', (event) ->

  class RaspBeeRemoteControlItem extends pimatic.DeviceItem

    constructor: (templData, @device) ->
      super(templData, @device)

    getItemTemplate: => 'raspbee-remote'

    onButtonPress: (button) =>
      @device.rest.buttonPressed({buttonId: "raspbee_#{@device.config.deviceID}_#{button}"}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

  class RaspBeeSwitchItem extends pimatic.SwitchItem

    constructor: (templData, @device) ->
      super(templData, @device)
      @getAttribute('presence').value.subscribe( =>
        @updateClass()
      )

    getItemTemplate: => 'raspbee-switch'

    afterRender: (elements) ->
      super(elements)
      @presenceEle = $(elements).find('.attr-presence')
      @updateClass()

    updateClass: ->
      value = @getAttribute('presence').value()
      if @presenceEle?
        switch value
          when true
            @presenceEle.addClass('value-present')
            @presenceEle.removeClass('value-absent')
          when false
            @presenceEle.removeClass('value-present')
            @presenceEle.addClass('value-absent')
          else
            @presenceEle.removeClass('value-absent')
            @presenceEle.removeClass('value-present')
        return


  class RaspBeeDimmerItem extends pimatic.SwitchItem

    constructor: (templData, @device) ->
      super(templData, @device)
      @getAttribute('presence').value.subscribe( =>
        @updateClass()
      )
      @dsliderId = "dimmer-#{templData.deviceId}"
      dimAttribute = @getAttribute('dimlevel')
      dimlevel = dimAttribute.value
      @dsliderValue = ko.observable(if dimlevel()? then dimlevel() else 0)
      dimAttribute.value.subscribe( (newDimlevel) =>
        @dsliderValue(newDimlevel)
        pimatic.try => @dsliderEle.slider('refresh')
      )

    getItemTemplate: => 'raspbee-dimmer'

    onSliderStop: ->
      @dsliderEle.slider('disable')
      @device.rest.changeDimlevelTo( {dimlevel: @dsliderValue()}, global: no).done(ajaxShowToast)
      .fail( =>
        pimatic.try => @dsliderEle.val(@getAttribute('dimlevel').value()).slider('refresh')
      ).always( =>
        pimatic.try( => @dsliderEle.slider('enable'))
      ).fail(ajaxAlertFail)

    afterRender: (elements) ->
      super(elements)
      @presenceEle = $(elements).find('.attr-presence')
      @updateClass()
      @dsliderEle = $(elements).find('#' + @dsliderId)
      @dsliderEle.slider()
      $(elements).find('.ui-slider').addClass('no-carousel-slide')
      $('#index').on("slidestop", " #item-lists #"+@dsliderId , (event) ->
          ddev = ko.dataFor(this)
          ddev.onSliderStop()
          return
      )

    updateClass: ->
      value = @getAttribute('presence').value()
      if @presenceEle?
        switch value
          when true
            @presenceEle.addClass('value-present')
            @presenceEle.removeClass('value-absent')
          when false
            @presenceEle.removeClass('value-present')
            @presenceEle.addClass('value-absent')
          else
            @presenceEle.removeClass('value-absent')
            @presenceEle.removeClass('value-present')
        return

  class RaspBeeCTItem extends RaspBeeDimmerItem
    constructor: (templData, @device) ->
      super(templData, @device)
      #COLOR
      @csliderId = "color-#{templData.deviceId}"
      colorAttribute = @getAttribute('ct')
      unless colorAttribute?
        throw new Error("A dimmer device needs an color attribute!")
      color = colorAttribute.value
      @csliderValue = ko.observable(if color()? then color() else 0)
      colorAttribute.value.subscribe( (newColor) =>
        @csliderValue(newColor)
        pimatic.try => @csliderEle.slider('refresh')
      )

    getItemTemplate: => 'raspbee-ct'

    onSliderStop2: ->
      @csliderEle.slider('disable')
      @device.rest.setCT( {colorCode: @csliderValue()}, global: no).done(ajaxShowToast)
      .fail( =>
        pimatic.try => @csliderEle.val(@getAttribute('ct').value()).slider('refresh')
      ).always( =>
        pimatic.try( => @csliderEle.slider('enable'))
      ).fail(ajaxAlertFail)

    afterRender: (elements) ->
      @csliderEle = $(elements).find('#' + @csliderId)
      @csliderEle.slider()
      super(elements)
      $('#index').on("slidestop", " #item-lists #"+@csliderId, (event) ->
          cddev = ko.dataFor(this)
          cddev.onSliderStop2()
          return
      )

##############################################################
# RaspBeeRGBItem
##############################################################
  class RaspBeeRGBItem extends RaspBeeDimmerItem

    constructor: (templData, @device) ->
      super(templData, @device)
      @_colorChanged = false
      #COLOR
      @pickId = "pick-#{templData.deviceId}"

    getItemTemplate: => 'raspbee-rgb'

    afterRender: (elements) ->
      super(elements)
      $(elements).on("dragstop.spectrum","#"+@pickId, (color) =>
          @_changeColor(color)
      )
      @colorPicker = $(elements).find('.light-color')
      @colorPicker.spectrum
        preferredFormat: 'hsv'
        showButtons: false
        allowEmpty: true
        showInput: true
      $('.sp-container').addClass('ui-corner-all ui-shadow')

    _changeColor: (color) ->
      r = @colorPicker.spectrum('get').toRgb()['r']
      g = @colorPicker.spectrum('get').toRgb()['g']
      b = @colorPicker.spectrum('get').toRgb()['b']
      @device.rest.changeHueSatValTo(
        {hue: @colorPicker.spectrum('get').toHsv()['h'] / 360 * 100,
        sat: @colorPicker.spectrum('get').toHsv()['s'] * 100},
        global: no
      )
      return @device.rest.setRGB(
          {r: r, g: g, b: b}, global: no
        ).then(ajaxShowToast, ajaxAlertFail)


##############################################################
# RaspBeeRGBCTItem
##############################################################
  class RaspBeeRGBCTItem extends RaspBeeDimmerItem

    constructor: (templData, @device) ->
      super(templData, @device)
      @_colorChanged = false
      @csliderId = "color-#{templData.deviceId}"
      colorAttribute = @getAttribute('ct')
      unless colorAttribute?
        throw new Error("A dimmer device needs an color attribute!")
      color = colorAttribute.value
      @csliderValue = ko.observable(if color()? then color() else 0)
      colorAttribute.value.subscribe( (newColor) =>
        @csliderValue(newColor)
        pimatic.try => @csliderEle.slider('refresh')
      )
      @pickId = "pick-#{templData.deviceId}"

    getItemTemplate: => 'raspbee-rgbct'

    onSliderStop2: ->
      @csliderEle.slider('disable')
      @device.rest.setCT( {colorCode: @csliderValue()}, global: no).done(ajaxShowToast)
      .fail( =>
        pimatic.try => @csliderEle.val(@getAttribute('ct').value()).slider('refresh')
      ).always( =>
        pimatic.try( => @csliderEle.slider('enable'))
      ).fail(ajaxAlertFail)

    afterRender: (elements) ->
      @csliderEle = $(elements).find('#' + @csliderId)
      @csliderEle.slider()
      super(elements)
      $('#index').on("slidestop", " #item-lists #"+@csliderId, (event) ->
          cddev = ko.dataFor(this)
          cddev.onSliderStop2()
          return
      )
      $(elements).on("dragstop.spectrum","#"+@pickId, (color) =>
          @_changeColor(color)
      )
      @colorPicker = $(elements).find('.light-color')
      @colorPicker.spectrum
        preferredFormat: 'hsv'
        showButtons: false
        allowEmpty: true
        showInput: true
      $('.sp-container').addClass('ui-corner-all ui-shadow')

    _changeColor: (color) ->
      r = @colorPicker.spectrum('get').toRgb()['r']
      g = @colorPicker.spectrum('get').toRgb()['g']
      b = @colorPicker.spectrum('get').toRgb()['b']
      @device.rest.changeHueSatValTo(
        {hue: @colorPicker.spectrum('get').toHsv()['h'] / 360 * 100,
        sat: @colorPicker.spectrum('get').toHsv()['s'] * 100},
        global: no
      )
      return @device.rest.setRGB(
          {r: r, g: g, b: b}, global: no
        ).then(ajaxShowToast, ajaxAlertFail)



##############################################################
# RaspBeeGroupRGBCTItem
##############################################################
  class RaspBeeGroupRGBCTItem extends RaspBeeRGBCTItem

    getItemTemplate: => 'raspbee-group-rgbct'


  class RaspBeeSystemItem extends pimatic.DeviceItem
    constructor: (templData, @device) ->
      super(templData, @device)
      @lbutID = "lbutton-#{templData.deviceId}"
      @sbutID = "sbutton-#{templData.deviceId}"

    getItemTemplate: => 'raspbee-system'

    afterRender: (elements) ->
      super(elements)

    setLightDiscovery: ->
      @device.rest.setLightDiscovery(global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    setSensorDiscovery: ->
      @device.rest.setSensorDiscovery(global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    setBackup: ->
      @device.rest.setBackup(global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    setConfig: ->
      @device.rest.setConfig(global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)


  class RaspBeeMultiItem extends pimatic.DeviceItem
    constructor: (templData, @device) ->
      super(templData, @device)
      if "presence" in @device.config.supports
        @getAttribute('presence').value.subscribe( =>
          @updateClass()
        )

    getItemTemplate: => 'device'

    afterRender: (elements) ->
      super(elements)
      if "presence" in @device.config.supports
        @presenceEle = $(elements).find('.attr-presence')
        @updateClass()

    updateClass: ->
      value = @getAttribute('presence').value()
      if @presenceEle?
        switch value
          when true
            @presenceEle.addClass('value-present')
            @presenceEle.removeClass('value-absent')
          when false
            @presenceEle.removeClass('value-present')
            @presenceEle.addClass('value-absent')
          else
            @presenceEle.removeClass('value-absent')
            @presenceEle.removeClass('value-present')
      return

  pimatic.templateClasses['raspbee-switch'] = RaspBeeSwitchItem
  pimatic.templateClasses['raspbee-dimmer'] = RaspBeeDimmerItem
  pimatic.templateClasses['raspbee-ct'] = RaspBeeCTItem
  pimatic.templateClasses['raspbee-rgb'] = RaspBeeRGBItem
  pimatic.templateClasses['raspbee-rgbct'] = RaspBeeRGBCTItem
  pimatic.templateClasses['raspbee-remote'] = RaspBeeRemoteControlItem
  pimatic.templateClasses['raspbee-system'] = RaspBeeSystemItem
  pimatic.templateClasses['raspbee-group-rgbct'] = RaspBeeGroupRGBCTItem
  pimatic.templateClasses['raspbee-multi'] = RaspBeeMultiItem
