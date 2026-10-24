import QtQuick

// Keep delegates for unchanged assets when Backend publishes a new list snapshot.
ListModel {
    id: model
    dynamicRoles: true
    property var records: []
    onRecordsChanged: synchronize()
    function synchronize() {
        const rows = records || []
        const wanted = new Set(rows.map(row => row.id))
        const keys = []
        for (let i = count - 1; i >= 0; --i)
            if (!wanted.has(get(i).assetKey)) remove(i)
        for (let i = 0; i < count; ++i) keys.push(get(i).assetKey)
        for (let i = 0; i < rows.length; ++i) {
            const row = rows[i], signature = JSON.stringify(row)
            if (keys[i] !== row.id) {
                const old = keys.indexOf(row.id, i)
                if (old >= 0) {
                    move(old, i, 1)
                    keys.splice(i, 0, keys.splice(old, 1)[0])
                } else {
                    insert(i, {assetKey: row.id, recordData: row, fingerprint: signature})
                    keys.splice(i, 0, row.id)
                }
            }
            if (get(i).fingerprint !== signature)
                set(i, {assetKey: row.id, recordData: row, fingerprint: signature})
        }
    }
}
