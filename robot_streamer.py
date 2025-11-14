#!/usr/bin/env python3
import socket
import struct
import threading
import time
import json
import math
import cv2

SUB_PORT    = 5007   # suscripciones de vídeo
CMD_PORT    = 5005   # comandos del perro
MJPG_MAGIC  = 0x4D4A5047
MAX_PAYLOAD = 1300   # bytes de JPEG por datagrama
FPS         = 20

current_client = None   # (ip, video_port)
current_cmd    = "STOP"

# ---------- Utilidad: header MJPEG ----------
def build_header(seq, frame_len, frag_idx, frag_cnt):
    ts_ms = int(time.time() * 1000)
    ts_hi = (ts_ms >> 32) & 0xffffffff
    ts_lo = ts_ms & 0xffffffff
    return struct.pack('!IIIIIHH',
                       MJPG_MAGIC,
                       seq,
                       ts_hi,
                       ts_lo,
                       frame_len,
                       frag_idx,
                       frag_cnt)

# ---------- 1. Loop de suscripciones (UDP 5007) ----------
def sub_loop():
    global current_client
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('', SUB_PORT))
    print(f"[SUB] Escuchando suscripciones en UDP {SUB_PORT}")
    while True:
        data, addr = sock.recvfrom(2048)
        print(f"[SUB] Datagrama desde {addr}: {data!r}")
        try:
            msg = json.loads(data.decode('utf-8'))
        except Exception as e:
            print("[SUB] Error parseando JSON:", e)
            continue

        if msg.get('type') == 'subscribe':
            video_port = int(msg.get('video_port', 5600))
            current_client = (addr[0], video_port)
            print(f"[SUB] Nuevo cliente vídeo: {current_client}")

# ---------- 2. Loop de comandos (UDP 5005) ----------
def handle_command(cmd):
    global current_cmd
    current_cmd = cmd
    print("[CMD] Comando recibido:", cmd)
    # TODO: aquí conectas los gaits del perro

def cmd_loop():
    global current_client
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('', CMD_PORT))
    print(f"[CMD] Escuchando comandos en UDP {CMD_PORT}")
    while True:
        data, addr = sock.recvfrom(2048)
        try:
            msg = json.loads(data.decode('utf-8'))
        except Exception as e:
            print("[CMD] Error parseando JSON:", e)
            continue

        # Fallback: si todavía no tenemos cliente de vídeo, usa la IP de quien mandó el comando
        if current_client is None:
            current_client = (addr[0], 5600)
            print(f"[CMD] No había cliente vídeo; usando {current_client} como destino")

        if msg.get('type') == 'cmd':
            cmd = msg.get('value')
            if cmd:
                handle_command(cmd)

# ---------- 3. Video loop ----------
def video_loop():
    global current_client

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("[VIDEO] No se pudo abrir la cámara USB (VideoCapture(0))")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    seq = 0

    print("[VIDEO] Iniciando envío de video")
    while True:
        if current_client is None:
            time.sleep(0.1)
            continue

        ok, frame = cap.read()
        if not ok:
            print("[VIDEO] Error capturando frame")
            continue

        ok, jpeg = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
        if not ok:
            continue

        data = jpeg.tobytes()
        frame_len = len(data)
        frag_cnt = math.ceil(frame_len / MAX_PAYLOAD)

        ip, port = current_client

        for frag_idx in range(frag_cnt):
            start = frag_idx * MAX_PAYLOAD
            end   = min(start + MAX_PAYLOAD, frame_len)
            payload = data[start:end]

            hdr = build_header(seq, frame_len, frag_idx, frag_cnt)
            packet = hdr + payload

            sock.sendto(packet, (ip, port))

        if seq % 30 == 0:
            print(f"[VIDEO] Enviado frame {seq} a {current_client} "
                  f"(len={frame_len}, frags={frag_cnt})")

        seq = (seq + 1) & 0xffffffff
        time.sleep(1.0 / FPS)

# ---------- Main ----------
if __name__ == "__main__":
    threading.Thread(target=sub_loop, daemon=True).start()
    threading.Thread(target=cmd_loop, daemon=True).start()
    video_loop()
