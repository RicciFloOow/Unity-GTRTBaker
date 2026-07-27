using UnityEngine;

namespace GTRTBaker
{
    public enum BakeEnvironmentMode
    {
        Agnostic,
        EditorOffline,
        EditorPlayMode,
        RuntimeBuild
    }

    public struct BakeSettings
    {
        public string BakeName;
        public BakeEnvironmentMode EnvMode;
        public IBakeStopStrategy StopStrategy;
    }
}