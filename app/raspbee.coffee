
merge = Array.prototype.concat

$(document).on 'templateinit', (event) ->

  class RaspBeeRemoteControlItem extends pimatic.DeviceItem

    constructor: (templData, @device) ->
      super(templData, @device)
      console.log(@device.attributes())

    getItemTemplate: => 'raspbeeremote'

    onButtonPress: (button) =>
      @device.rest.buttonPressed({buttonId: button.id}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

  pimatic.templateClasses['raspbeeremote'] = RaspBeeRemoteControlItem
