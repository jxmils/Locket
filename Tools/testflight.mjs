import { readFileSync } from 'node:fs'
import { sign } from 'node:crypto'
import { join } from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'

const [mode, version] = process.argv.slice(2)
if (!['lookup', 'wait'].includes(mode) || !/^\d+$/.test(version)) throw Error('Expected lookup or wait and a build number')
const app = '6837036852'
const group = 'a4c501a3-238f-48d4-9452-82889ef3a3ba'
const { APP_STORE_CONNECT_KEY_ID: kid, APP_STORE_CONNECT_ISSUER_ID: iss, API_PRIVATE_KEYS_DIR } = process.env
const key = readFileSync(join(API_PRIVATE_KEYS_DIR, 'AuthKey_' + kid + '.p8'))
const encode = obj => Buffer.from(JSON.stringify(obj)).toString('base64url')
async function apple(path, body) {
  const now = Math.floor(Date.now()/1000)
  const unsigned = encode({ alg:'ES256',kid,typ:'JWT' }) + '.' + encode({ iss,iat:now-10,exp:now+300,aud:'appstoreconnect-v1' })
  const sig = sign('sha256',Buffer.from(unsigned),{key,dsaEncoding:'ieee-p1363'}).toString('base64url')
  const response = await fetch('https://api.appstoreconnect.apple.com/v1/' + path,{
    method: body ? 'POST' : 'GET',
    headers: {Authorization:'Bearer ' + unsigned + '.' + sig,'Content-Type':'application/json'},
    body: body ? JSON.stringify(body) : undefined
  })
  if (!response.ok) throw Error('Apple returned ' + response.status + ' for ' + path + ': ' + await response.text())
  return response.status === 204 ? null : (await response.json()).data
}
const lookup = () => apple('builds?' + new URLSearchParams({'filter[app]':app,'filter[version]':version}))
if (mode === 'lookup') {
  console.log((await lookup()).length ? 'present' : 'missing')
} else {
  let ready = false
  for (let attempt=0; attempt<100; attempt++) {
    const [build] = await lookup()
    if (build) {
      const state = build.attributes.processingState
      if (state === 'FAILED' || state === 'INVALID') throw Error('Apple processing ' + state)
      if (state === 'VALID') {
        const assigned = await apple('betaGroups/' + group + '/builds?limit=200')
        if (!assigned.some(item => item.id === build.id)) {
          await apple('betaGroups/' + group + '/relationships/builds',{data:[{type:'builds',id:build.id}]})
        }
        const detail = await apple('builds/' + build.id + '/buildBetaDetail')
        if (detail.attributes.internalBuildState === 'IN_BETA_TESTING') {
          console.log('Stampnote build ' + version + ' is ready for internal testing. https://appstoreconnect.apple.com/apps/' + app + '/testflight/ios/' + build.id)
          ready = true
          break
        }
      }
    }
    await delay(15000)
  }
  if (!ready) throw Error('Apple has not finished processing. Re-run this job to check the existing build.')
}
