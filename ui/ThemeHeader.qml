import QtQuick
Rectangle {
    color: Theme.surfacePrimary
    readonly property bool themedGradient: Theme.gradient
    gradient: themedGradient ? headerGradient : null
    Gradient {
        id: headerGradient; orientation: Gradient.Horizontal
        GradientStop {position:0;color:Theme.surfacePrimary}
        GradientStop {position:1;color:Theme.surfaceSecondary}
    }
}
