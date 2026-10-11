// pack-asar.js -- 把目录重新打包成 Electron 的 app.asar
// 用法: node pack-asar.js <源目录> <输出.asar>
// asar 格式: [UInt32 4][UInt32 headerBufLength][UInt32 payloadSize][UInt32 jsonLength][json][padding][文件数据...]
const fs = require('node:fs')
const path = require('node:path')

const src = process.argv[2]
const out = process.argv[3]
if (!src || !out) {
  console.error('用法: node pack-asar.js <源目录> <输出.asar>')
  process.exit(1)
}

const header = { files: {} }
const queue = []

function addEntries(dir, node) {
  for (const name of fs.readdirSync(dir).sort()) {
    const full = path.join(dir, name)
    const stat = fs.statSync(full)
    if (stat.isDirectory()) {
      const child = {}
      node[name] = { files: child }
      addEntries(full, child)
    } else {
      node[name] = { size: stat.size, offset: '0' }
      queue.push({ node: node[name], full })
    }
  }
}
addEntries(src, header.files)

let offset = 0
for (const item of queue) {
  item.node.offset = String(offset)
  offset += item.node.size
}

const json = Buffer.from(JSON.stringify(header), 'utf8')
const pad = (4 - (json.length % 4)) % 4
const payloadSize = 4 + json.length + pad
const headerBufLength = 4 + payloadSize

const sizeBuf = Buffer.alloc(8)
sizeBuf.writeUInt32LE(4, 0)
sizeBuf.writeUInt32LE(headerBufLength, 4)

const headerBuf = Buffer.alloc(headerBufLength)
headerBuf.writeUInt32LE(payloadSize, 0)
headerBuf.writeUInt32LE(json.length, 4)
json.copy(headerBuf, 8)

const fd = fs.openSync(out, 'w')
try {
  fs.writeSync(fd, sizeBuf)
  fs.writeSync(fd, headerBuf)
  for (const item of queue) fs.writeSync(fd, fs.readFileSync(item.full))
} finally {
  fs.closeSync(fd)
}

console.log(`packed ${queue.length} files -> ${out} (${fs.statSync(out).size} bytes)`)
