pragma Singleton
import QtQuick
QtObject {
    id: theme
    readonly property var settings: typeof backend !== "undefined" ? backend.theme : ({primary:"#a8dfcf",secondary:"#afd5f0",mode:"single"})
    readonly property bool gradient: settings.mode === "gradient"
    // Small controls retain contrast on white; large surfaces preserve light colors.
    function accessible(value) {
        let c = Qt.darker(value, 1)
        for(let i=0;i<40 && luminance(c)>.183;i++)c=Qt.darker(c,1.08)
        return c
    }
    function luminance(c) {
        function linear(v){return v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4)}
        return .2126*linear(c.r)+.7152*linear(c.g)+.0722*linear(c.b)
    }
    function mix(a,b,t){return Qt.rgba(a.r*(1-t)+b.r*t,a.g*(1-t)+b.g*t,a.b*(1-t)+b.b*t,1)}
    function alpha(c,a){return Qt.rgba(c.r,c.g,c.b,a)}
    readonly property color rawPrimary: settings.primary || "#a8dfcf"
    readonly property color rawSecondary: settings.secondary || "#afd5f0"
    readonly property color preferredInk: "#4b5358"
    function readableInk(a,b,preferred) {
        let c = preferred || preferredInk
        const background = Math.min(luminance(a),luminance(b))
        for(let i=0;i<40 && (background+.05)/(luminance(c)+.05)<4.5;i++)c=Qt.darker(c,1.04)
        return c
    }
    readonly property color darkSurfaceInk: readableInk(rawPrimary,gradient?rawSecondary:rawPrimary)
    // Preserve the light/dark surface classification when softening the labels.
    function darkTextFits(c) { return (luminance(c)+.05)/(luminance(Qt.rgba(23/255,43/255,52/255,1))+.05)>=4.5 }
    readonly property bool lightSurface: darkTextFits(rawPrimary)&&(!gradient||darkTextFits(rawSecondary))
    // Mixed light/dark custom gradients use darkened endpoints for a shared white label.
    readonly property color surfacePrimary: lightSurface ? rawPrimary : accessible(rawPrimary)
    readonly property color surfaceSecondary: lightSurface ? rawSecondary : accessible(rawSecondary)
    readonly property color surfaceInk: lightSurface ? darkSurfaceInk : "#ffffff"
    readonly property color buttonInk: "#59636a"
    readonly property color buttonSurfaceInk: lightSurface ? readableInk(rawPrimary,gradient?rawSecondary:rawPrimary,buttonInk) : "#ffffff"
    readonly property color buttonChosenInk: readableInk(softPressed,gradient?mix(secondary,Qt.rgba(1,1,1,1),.73):softPressed,buttonInk)
    function surfaceState(c,down,hovered) {
        return lightSurface ? mix(c,Qt.rgba(1,1,1,1),down ? .22 : hovered ? .12 : 0)
                            : Qt.darker(c,down?1.25:hovered?1.09:1)
    }
    // A richer solid swatch keeps the white check visible over photos without dark outlines.
    function photoCheckColor(c) {
        if(c.hsvSaturation < .04)return accessible(c)
        let fill=Qt.hsva(c.hsvHue,Math.max(.72,Math.min(.9,c.hsvSaturation*1.5)),Math.min(.88,c.hsvValue),1)
        // Preserve the hue and saturation; cap brightness for a clear white icon.
        for(let i=0;i<40 && luminance(fill)>.30;i++)fill=Qt.darker(fill,1.04)
        return fill
    }
    readonly property color checkFill: photoCheckColor(rawPrimary)
    readonly property color primary: accessible(rawPrimary)
    readonly property color secondary: accessible(rawSecondary)
    readonly property color ink: readableInk(softPressed,gradient?mix(secondary,Qt.rgba(1,1,1,1),.73):softPressed)
    readonly property color hover: Qt.darker(primary,1.09)
    readonly property color pressed: Qt.darker(primary,1.25)
    readonly property color soft: mix(primary,Qt.rgba(1,1,1,1),.88)
    readonly property color softHover: mix(primary,Qt.rgba(1,1,1,1),.81)
    readonly property color softPressed: mix(primary,Qt.rgba(1,1,1,1),.73)
    readonly property color secondarySoft: mix(secondary,Qt.rgba(1,1,1,1),.88)
    readonly property color focus: mix(primary,Qt.rgba(1,1,1,1),.25)
    readonly property color onDark: mix(primary,Qt.rgba(1,1,1,1),.55)
}
