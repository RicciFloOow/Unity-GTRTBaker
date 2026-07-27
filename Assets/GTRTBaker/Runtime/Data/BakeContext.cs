using System;
using UnityEngine;

namespace GTRTBaker
{
    public class BakeContext
    {
        public BakeSettings Settings;
        public int CurrentSPP;
        public float StartTime;

        public Action OnCompleted;
        public Action OnCanceled;
        public Action<Exception> OnFailed;
        public Action<float> OnProgress;
    }
}