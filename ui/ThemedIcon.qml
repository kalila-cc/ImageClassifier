import QtQuick
Image {
    property string name: "crop-free"
    property color ink: Theme.primary
    source: "image://media/icon/"+name+"/"+ink.toString().substring(1)
    retainWhileLoading: true
    cache: true
}
