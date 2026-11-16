// Mã máy ổn định (băm): định danh máy cho MCP bridge của runner và để biết trình duyệt / agent / người dùng có cùng máy không.
// Không gửi mã gốc đi đâu. Kiểm thử: FLYGO_MACHINE_ID ghi đè (giả nhiều máy trên một máy).
// Cùng công thức với app Flygo Chat (lib/browser/machine_id.dart): sha256("flygo-machine/v1:" + mã gốc viết thường), 32 ký tự hex.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { hostname } from 'node:os';

let cached: string | null | undefined;

function raw(): string | null {
  try {
    if (process.platform === 'linux') return readFileSync('/etc/machine-id', 'utf8').trim() || readFileSync('/var/lib/dbus/machine-id', 'utf8').trim();
    if (process.platform === 'darwin') {
      const out = execFileSync('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice'], { encoding: 'utf8', timeout: 5000 });
      return /"IOPlatformUUID"\s*=\s*"([^"]+)"/.exec(out)?.[1] ?? null;
    }
    if (process.platform === 'win32') {
      const out = execFileSync('reg', ['query', 'HKLM\\SOFTWARE\\Microsoft\\Cryptography', '/v', 'MachineGuid'], { encoding: 'utf8', timeout: 5000, windowsHide: true });
      return /MachineGuid\s+REG_SZ\s+(\S+)/.exec(out)?.[1] ?? null;
    }
  } catch {}
  return null;
}

export function machineId(): string | null {
  if (process.env.FLYGO_MACHINE_ID) return process.env.FLYGO_MACHINE_ID;
  if (cached !== undefined) return cached;
  const r = raw();
  cached = r ? createHash('sha256').update(`flygo-machine/v1:${r.trim().toLowerCase()}`).digest('hex').slice(0, 32) : null;
  return cached;
}

export const machineName = () => process.env.FLYGO_MACHINE_NAME || hostname().replace(/\.(local|lan|home)$/i, '');
