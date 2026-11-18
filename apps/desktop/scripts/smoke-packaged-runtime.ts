/** Validate the assembled application, including native Office conversion outside ASAR. */
import { join } from 'node:path'
import { parseArgs } from 'node:util'
import { desktopArtifactOutput, resolveDesktopBuildTarget, resolveDesktopTargetBuildPaths } from './desktop-build-paths.mjs'
import { readDesktopRuntime, verifyDesktopRuntime } from '../src/runtime-tree.ts'
import { verifyWindowsCode } from './windows-runtime-signature.mjs'
import { smokePreparedRuntime } from './smoke-prepared-runtime.ts'
import { resolveDesktopPackageTarget } from './package-target.ts'

const paths = resolveDesktopTargetBuildPaths()
const { values } = parseArgs({ options: { unsigned: { type: 'boolean', default: false }, 'skip-notarization': { type: 'boolean', default: false } }, allowPositionals: false })
const target = resolveDesktopBuildTarget()
const windows = target === 'win-x64'
const linux = target === 'linux-x64'
const artifacts = desktopArtifactOutput(paths, { unsigned: values.unsigned, skipNotarization: values['skip-notarization'] }).directory

function applicationDirectory(): string {
  if (windows) return join(artifacts, 'win-unpacked')
  if (linux) return join(artifacts, 'linux-unpacked')
  return join(artifacts, target === 'mac-arm64' ? 'mac-arm64' : 'mac', 'DeepSeek Harness.app', 'Contents')
}

function resourcesDirectory(application: string): string {
  return join(application, windows || linux ? 'resources' : 'Resources')
}

function applicationExecutable(application: string, resources: string): string {
  if (windows) return join(application, 'DeepSeek Harness.exe')
  if (linux) return join(resources, 'runtime', 'primary-runtime', 'dependencies', 'node', 'bin', 'node')
  return join(application, 'MacOS', 'DeepSeek Harness')
}

const application = applicationDirectory()
const resources = resourcesDirectory(application)
const executable = applicationExecutable(application, resources)
const descriptor = await verifyDesktopRuntime(paths.dsh, readDesktopRuntime(paths.dsh).release.version,
  resolveDesktopPackageTarget(target))
if (windows && !values.unsigned) await verifyWindowsCode(application)
await smokePreparedRuntime(linux ? join(resources, 'dsh') : join(resources, 'app.asar', 'dsh'),
  executable, join(resources, 'runtime'), descriptor)
