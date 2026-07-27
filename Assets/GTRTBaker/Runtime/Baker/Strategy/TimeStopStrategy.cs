using UnityEngine;

namespace GTRTBaker
{
    public class TimeStopStrategy : IBakeStopStrategy
    {
        private readonly float m_maxSeconds;
        public TimeStopStrategy(float maxSeconds) => m_maxSeconds = maxSeconds;


        public float GetProgress(BakeContext context)
        {
            return (Time.realtimeSinceStartup - context.StartTime) / m_maxSeconds;
        }

        public bool IsFinished(BakeContext context)
        {
            return (Time.realtimeSinceStartup - context.StartTime) >= m_maxSeconds;
        }
    }
}