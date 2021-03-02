
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

  class RaspBeeCoverItem extends pimatic.DeviceItem # extends pimatic.SwitchItem

    constructor: (templData, @device) ->
      super(templData, @device)
      @dsliderId = "dimmer-#{templData.deviceId}"
      liftAttribute = @getAttribute('lift')
      liftlevel = liftAttribute.value
      @dsliderValue = ko.observable(if liftlevel()? then liftlevel() else 0)
      liftAttribute.value.subscribe( (newLiftlevel) =>
        @dsliderValue(newLiftlevel)
        pimatic.try => @dsliderEle.slider('refresh')
      )


    getItemTemplate: => 'raspbee-cover'

    afterRender: (elements) ->
      super(elements)

      @closeButton = $(elements).find('[name=closeButton]')
      @stopButton = $(elements).find('[name=stopButton]')
      @openButton = $(elements).find('[name=openButton]')
      @updateActionButtons()

      @getAttribute('action')?.value.subscribe( => @updateActionButtons() )

      @getAttribute('presence').value.subscribe( =>
        @updateClass()
      )

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

    modeClose: -> @changeActionTo "close"
    modeStop: -> @changeActionTo "stop"
    modeOpen: -> @changeActionTo "open"

    updateActionButtons: =>
      actionAttr = @getAttribute('action')?.value()
      switch actionAttr
        when 'close'
          @closeButton.addClass('ui-btn-active')
          @stopButton.removeClass('ui-btn-active')
          @openButton.removeClass('ui-btn-active')
        when 'stop'
          @closeButton.removeClass('ui-btn-active')
          @stopButton.addClass('ui-btn-active')
          @openButton.removeClass('ui-btn-active')
        when 'open'
          @closeButton.removeClass('ui-btn-active')
          @stopButton.removeClass('ui-btn-active')
          @openButton.addClass('ui-btn-active')
      return

    onSliderStop: ->
      @dsliderEle.slider('disable')
      @device.rest.changeLiftTo( {lift: @dsliderValue()}, global: no).done(ajaxShowToast)
      .fail( =>
        pimatic.try => @dsliderEle.val(@getAttribute('lift').value()).slider('refresh')
      ).always( =>
        pimatic.try( => @dsliderEle.slider('enable'))
      ).fail(ajaxAlertFail)

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

    changeActionTo: (_action) ->
      @device.rest.changeActionTo({action: _action}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

  class RaspBeeWarningItem extends pimatic.DeviceItem # extends pimatic.SwitchItem

    constructor: (templData, @device) ->
      super(templData, @device)
      warningAttribute = @getAttribute('warning')
      warning = warningAttribute.value


    getItemTemplate: => 'raspbee-warning'

    afterRender: (elements) ->
      super(elements)

      @offButton = $(elements).find('[name=offButton]')
      @silentButton = $(elements).find('[name=silentButton]')
      @soundButton = $(elements).find('[name=soundButton]')
      @longButton = $(elements).find('[name=longButton]')
      @updateWarningButtons()

      @getAttribute('warning')?.value.subscribe( => @updateWarningButtons() )

      @getAttribute('presence').value.subscribe( =>
        @updateClass()
      )

      @presenceEle = $(elements).find('.attr-presence')
      @updateClass()

    modeOff: -> @changeWarningTo "off"
    modeSilent: -> @changeWarningTo "silent"
    modeSound: -> @changeWarningTo "sound"
    modeLong: -> @changeWarningTo "long"

    updateWarningButtons: =>
      warningAttr = @getAttribute('warning')?.value()
      switch warningAttr
        when 'off'
          @offButton.addClass('ui-btn-active')
          @silentButton.removeClass('ui-btn-active')
          @soundButton.removeClass('ui-btn-active')
          @longButton.removeClass('ui-btn-active')
        when 'silent'
          @offButton.removeClass('ui-btn-active')
          @silentButton.addClass('ui-btn-active')
          @soundButton.removeClass('ui-btn-active')
          @longButton.removeClass('ui-btn-active')
        when 'sound'
          @offButton.removeClass('ui-btn-active')
          @silentButton.removeClass('ui-btn-active')
          @soundButton.addClass('ui-btn-active')
          @longButton.removeClass('ui-btn-active')
        when 'long'
          @offButton.removeClass('ui-btn-active')
          @silentButton.removeClass('ui-btn-active')
          @soundButton.removeClass('ui-btn-active')
          @longButton.addClass('ui-btn-active')
      return

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

    changeWarningTo: (_warning) ->
      @device.rest.changeWarningTo({warning: _warning}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)


  pimatic.templateClasses['raspbee-switch'] = RaspBeeSwitchItem
  pimatic.templateClasses['raspbee-dimmer'] = RaspBeeDimmerItem
  pimatic.templateClasses['raspbee-ct'] = RaspBeeCTItem
  pimatic.templateClasses['raspbee-rgb'] = RaspBeeRGBItem
  pimatic.templateClasses['raspbee-rgbct'] = RaspBeeRGBCTItem
  pimatic.templateClasses['raspbee-remote'] = RaspBeeRemoteControlItem
  pimatic.templateClasses['raspbee-system'] = RaspBeeSystemItem
  pimatic.templateClasses['raspbee-group-rgbct'] = RaspBeeGroupRGBCTItem
  pimatic.templateClasses['raspbee-multi'] = RaspBeeMultiItem
  pimatic.templateClasses['raspbee-cover'] = RaspBeeCoverItem
  pimatic.templateClasses['raspbee-warning'] = RaspBeeWarningItem
