import QtQuick
import "../ui"

DirectoryTree {
    width: 220; height: 400
    rootPath: "/root"
    property int selections: 0
    property string openedPath: ""
    property string createdUnder: ""
    property string renamedPath: ""
    onNewDirectoryRequested: path => createdUnder = path
    onRenameDirectoryRequested: (path,name) => renamedPath = path
    onDirectorySelected: path => {selectedPath = path; selections++}
    onDirectoryOpened: path => {openedPath = path; workingPath = path}
    directories: [
        {path:"/root",name:"Root",depth:0,mediaCount:7},
        {path:"/root/a",name:"A",depth:1,mediaCount:7},
        {path:"/root/a/nested",name:"Nested",depth:2,mediaCount:7},
        {path:"/root/b",name:"B",depth:1,mediaCount:0}
    ]
    function refreshFixture() { directories = directories.map(row => Object.assign({}, row, {mediaCount:8})) }
}
