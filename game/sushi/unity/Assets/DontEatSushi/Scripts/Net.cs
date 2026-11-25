// 別吃壽司 - 最簡單的連線層：一個人當主機，其他人用 IP 直連，主機負責轉發。不依賴任何外部套件。
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace DontEatSushi
{
    public class Net
    {
        public const int Port = 7777;
        public bool isHost, connected;
        public int myId;
        public string error = "";
        /// 收到的訊息，格式是「發送者編號|內容」
        public readonly ConcurrentQueue<string> inbox = new ConcurrentQueue<string>();

        class Peer { public int id; public TcpClient tcp; public NetworkStream st; public readonly object sendLock = new object(); }

        TcpListener listener;
        readonly List<Peer> peers = new List<Peer>();
        Peer server;
        volatile bool running;
        int nextId = 1;

        public bool Host()
        {
            try { listener = new TcpListener(IPAddress.Any, Port); listener.Start(); }
            catch (Exception e) { error = e.Message; return false; }
            isHost = true; connected = true; myId = 0; running = true;
            new Thread(AcceptLoop) { IsBackground = true }.Start();
            return true;
        }

        void AcceptLoop()
        {
            while (running)
            {
                try
                {
                    var c = listener.AcceptTcpClient();
                    c.NoDelay = true;
                    var p = new Peer { id = nextId++, tcp = c, st = c.GetStream() };
                    lock (peers) peers.Add(p);
                    SendRaw(p, "hello|" + p.id);
                    inbox.Enqueue(p.id + "|join");
                    new Thread(() => ReadLoop(p)) { IsBackground = true }.Start();
                }
                catch { if (!running) return; }
            }
        }

        public bool Join(string ip)
        {
            try
            {
                var c = new TcpClient();
                c.NoDelay = true;
                var ar = c.BeginConnect(ip, Port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(3000)) { c.Close(); error = "連不上 " + ip; return false; }
                c.EndConnect(ar);
                server = new Peer { id = 0, tcp = c, st = c.GetStream() };
            }
            catch (Exception e) { error = e.Message; return false; }
            running = true; connected = true; myId = -1;
            new Thread(() => ReadLoop(server)) { IsBackground = true }.Start();
            return true;
        }

        void ReadLoop(Peer p)
        {
            var len = new byte[4];
            try
            {
                while (running)
                {
                    ReadFull(p.st, len, 4);
                    int n = BitConverter.ToInt32(len, 0);
                    if (n < 0 || n > 4000000) break;
                    var buf = new byte[n];
                    ReadFull(p.st, buf, n);
                    string msg = Encoding.UTF8.GetString(buf);
                    if (isHost)
                    {
                        string framed = p.id + "|" + msg;
                        Broadcast(framed, p.id);
                        inbox.Enqueue(framed);
                    }
                    else if (msg.StartsWith("hello|")) myId = int.Parse(msg.Substring(6));
                    else inbox.Enqueue(msg);
                }
            }
            catch { }
            if (!running) return;
            if (isHost)
            {
                lock (peers) peers.Remove(p);
                Broadcast(p.id + "|leave", -1);
                inbox.Enqueue(p.id + "|leave");
            }
            else { connected = false; inbox.Enqueue("0|closed"); }
        }

        static void ReadFull(NetworkStream s, byte[] b, int n)
        {
            int off = 0;
            while (off < n)
            {
                int r = s.Read(b, off, n - off);
                if (r <= 0) throw new Exception("closed");
                off += r;
            }
        }

        void SendRaw(Peer p, string msg)
        {
            var body = Encoding.UTF8.GetBytes(msg);
            var len = BitConverter.GetBytes(body.Length);
            try { lock (p.sendLock) { p.st.Write(len, 0, 4); p.st.Write(body, 0, body.Length); } }
            catch { }
        }

        void Broadcast(string framed, int except)
        {
            Peer[] list;
            lock (peers) list = peers.ToArray();
            foreach (var q in list) if (q.id != except) SendRaw(q, framed);
        }

        /// 把內容發給其他所有人。
        public void Send(string payload)
        {
            if (!connected) return;
            if (isHost) Broadcast("0|" + payload, -1);
            else if (server != null) SendRaw(server, payload);
        }

        public void Close()
        {
            running = false; connected = false;
            try { if (listener != null) listener.Stop(); } catch { }
            Peer[] list;
            lock (peers) { list = peers.ToArray(); peers.Clear(); }
            foreach (var q in list) { try { q.tcp.Close(); } catch { } }
            try { if (server != null) server.tcp.Close(); } catch { }
        }

        public static string LocalIP()
        {
            try
            {
                foreach (var a in Dns.GetHostEntry(Dns.GetHostName()).AddressList)
                    if (a.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(a)) return a.ToString();
            }
            catch { }
            return "127.0.0.1";
        }
    }
}
