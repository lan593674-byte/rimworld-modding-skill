using System;
using UnityEngine;

namespace GameTestLoader
{
    // 1.6 build: Unity's threaded log callback and a component's Update. Host.Waylith.cs is the 1.7 counterpart.
    internal static class Host
    {
        public static void ListenForErrors(Action<string> onError)
        {
            Application.logMessageReceivedThreaded += (condition, stackTrace, type) =>
            {
                if (type != LogType.Error && type != LogType.Exception && type != LogType.Assert) return;
                try { onError(condition); } catch { }
            };
        }

        public static void CallEveryFrame(Action update)
        {
            var host = new GameObject("GameTestLoader");
            UnityEngine.Object.DontDestroyOnLoad(host);
            host.AddComponent<FrameHook>().update = update;
        }
    }

    public sealed class FrameHook : MonoBehaviour
    {
        internal Action update;

        private void Update()
        {
            try { update?.Invoke(); }
            catch (Exception ex) { Verse.Log.Message("[TESTLOADER] FAIL frame hook: " + ex); }
        }
    }
}
