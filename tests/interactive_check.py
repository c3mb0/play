#!/usr/bin/env python3
"""Bounded real-helper checks; synthetic commands only, no personal transcripts."""
import json, os, select, struct, subprocess, time
from pathlib import Path
root = Path(__file__).resolve().parents[1]
helper = root / 'target/debug/pty_helper'
class Session:
    def __init__(self, argv=None):
        self.p = subprocess.Popen([helper, '--port'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.seq = 0
        self.events = []
        self.buffer = bytearray()
        self.send('spawn', spec={'executable':'/bin/sh','argv':argv or ['-i'], 'environment':{'PATH':'/usr/bin:/bin','TERM':'xterm-256color'}, 'cwd':'/tmp','attachment':'ctty','interactive':True,'terminal':{'dimensions':{'rows':24,'cols':80,'xpixel':0,'ypixel':0}}})
        self.until('spawned')
    def send(self, command, **data):
        self.seq += 1
        payload = json.dumps(dict(v=1,identity=dict(experiment='interactive',cell='check',session=str(self.p.pid)),seq=self.seq,command=command,**data)).encode()
        self.p.stdin.write(struct.pack('!I',len(payload))+payload); self.p.stdin.flush()
    def event(self, timeout=3):
        end=time.monotonic()+timeout
        while True:
            if len(self.buffer)>=4:
                n=struct.unpack('!I',self.buffer[:4])[0]
                if len(self.buffer)>=4+n:
                    e=json.loads(self.buffer[4:4+n]);del self.buffer[:4+n];self.events.append(e)
                    return e
            left=end-time.monotonic()
            if left<=0 or not select.select([self.p.stdout],[],[],max(left,0))[0]: raise TimeoutError()
            b=os.read(self.p.stdout.fileno(),65536)
            if not b: raise EOFError()
            self.buffer.extend(b)
    def until(self, name):
        while True:
            e=self.event()
            if e['event']==name:return e['data']
    def output_until(self, needle):
        output=b''
        while needle not in output:
            e=self.event()
            if e['event']=='pty_output':
                b=bytes.fromhex(e['data']['hex']);output+=b;self.send('credit',bytes=len(b))
            assert e['event']!='error',e
        return output
    def write(self,b):self.send('write',hex=b.hex())
    def close(self):
        if self.p.poll() is None:
            self.send('close');self.p.wait(timeout=3)
    def __enter__(self):return self
    def __exit__(self,*args):self.close()
with Session() as s:
    spawned=s.events[0]['data']; assert spawned['terminal_observation']['configuration']['dimensions']['cols']==80
    s.send('resize',rows=31,cols=97)
    assert s.until('resized')['cols']==97
    s.write(b'stty size\n'); assert b'31 97' in s.output_until(b'31 97')
    # Foreground job must receive SIGWINCH and be killed by close.
    s.write(b"trap 'echo WINCH' WINCH; echo READY\n")
    s.output_until(b'READY\r\n')
    s.send('resize',rows=33,cols=101);s.output_until(b'WINCH\r\n')
    s.write(b'set +H\n')
    s.write(b"stty -echo; sh -c 'echo CHILD:$$; exec sleep 100'\n")
    out=s.output_until(b'CHILD:')
    while not __import__('re').search(rb'CHILD:(\d+)\r\n',out):out+=s.output_until(b'\r\n')
    child=int(__import__('re').search(rb'CHILD:(\d+)\r\n',out)[1])
    # This controlled job owns the terminal foreground group.
    s.close()
    time.sleep(.1)
    try:os.kill(child,0)
    except ProcessLookupError:pass
    else:raise AssertionError(f'controlled child survived: {child}')
with Session(['-c', "stty -echo; printf START; head -c 200000 /dev/zero | tr '\\000' x; printf END"]) as s:
    out=b''
    while len(out)<65536:
        e=s.event()
        if e['event']=='pty_output':out+=bytes.fromhex(e['data']['hex'])
    assert len(out)==65536
    try:
        while True:
            e=s.event(.2)
            assert e['event']!='pty_output','credit window exceeded'
    except TimeoutError:pass
    s.send('credit',bytes=len(out))
    while b'END' not in out:
        e=s.event()
        if e['event']=='pty_output':
            b=bytes.fromhex(e['data']['hex']);out+=b;s.send('credit',bytes=len(b))
    assert out==b'START'+b'x'*200000+b'END',len(out)
    s.p.wait(timeout=3)
print('PASS: resize/readback, SIGWINCH, bounded credits, 200008 ordered bytes, controlled cleanup',flush=True)
