// Decode local diagnostic log samples; these files may contain camera imagery.
import fs from 'node:fs';
const [logPath, outputPrefix] = process.argv.slice(2);
if (!logPath || !outputPrefix) throw Error('Usage: node decode-c2d-samples.mjs LOG OUTPUT_PREFIX');
const groups = [];
let current;
for (const line of fs.readFileSync(logPath, 'utf8').split('\n')) {
  const header = line.match(/INPUT sample=(\d+) id=(\d+) fmt=(\d+) width=(\d+) height=(\d+) stride=(\d+)/);
  if (header) { current = {header: header[0], sample: header[1], planes: [new Map(), new Map()]}; groups.push(current); }
  const row = line.match(/ROW sample=(\d+) parity=([01]) y=(\d+) ([a-f0-9]{128})/);
  if (row && current && row[1] === current.sample) current.planes[Number(row[2])].set(Number(row[3]), Buffer.from(row[4], 'hex'));
}
for (const [i, group] of groups.entries()) for (let p=0;p<2;p++) {
  if (group.planes[p].size !== 48) throw Error(`Incomplete input ${i} parity ${p}`);
  const pixels = Buffer.concat(Array.from({length:48}, (_, y) => group.planes[p].get(y)));
  const file = `${outputPrefix}-${i}-p${p}.pgm`;
  fs.writeFileSync(file, Buffer.concat([Buffer.from('P5\n64 48\n255\n'), pixels]));
  console.log(file, group.header, 'range', Math.min(...pixels), Math.max(...pixels));
}
if (!groups.length) throw Error('No input samples found');
