//ref: SRP CommandBufferPool
using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    public class ObjectPool<T> where T : new()
    {
        readonly Stack<T> m_Stack = new Stack<T>();
        readonly UnityAction<T> m_ActionOnGet;
        readonly UnityAction<T> m_ActionOnRelease;
        readonly bool m_CollectionCheck;

        public ObjectPool(UnityAction<T> actionOnGet, UnityAction<T> actionOnRelease, bool collectionCheck = true)
        {
            m_ActionOnGet = actionOnGet;
            m_ActionOnRelease = actionOnRelease;
            m_CollectionCheck = collectionCheck;
        }

        public T Get()
        {
            T element = m_Stack.Count == 0 ? new T() : m_Stack.Pop();
            m_ActionOnGet?.Invoke(element);
            return element;
        }

        public void Release(T element)
        {
#if UNITY_EDITOR
            if (m_CollectionCheck && m_Stack.Count > 0 && m_Stack.Contains(element))
            {
                Debug.LogError("Internal error. Trying to destroy object that is already released to pool.");
                return;
            }
#endif
            m_ActionOnRelease?.Invoke(element);
            m_Stack.Push(element);
        }

        public struct PooledObject : IDisposable
        {
            readonly T m_ToReturn;
            readonly ObjectPool<T> m_Pool;

            internal PooledObject(T value, ObjectPool<T> pool)
            {
                m_ToReturn = value;
                m_Pool = pool;
            }

            void IDisposable.Dispose() => m_Pool.Release(m_ToReturn);
        }

        public PooledObject Get(out T v) => new PooledObject(v = Get(), this);
    }

    public static class CommandBufferPool
    {
        static ObjectPool<CommandBuffer> s_BufferPool = new ObjectPool<CommandBuffer>(null, x => x.Clear());

        public static CommandBuffer Get(string name = "")
        {
            var cmd = s_BufferPool.Get();
            cmd.name = name;
            return cmd;
        }

        public static void Release(CommandBuffer buffer) => s_BufferPool.Release(buffer);
    }

    public static class ListPool<T>
    {
        static readonly ObjectPool<List<T>> s_Pool = new ObjectPool<List<T>>(null, l => l.Clear());
        public static List<T> Get() => s_Pool.Get();
        public static ObjectPool<List<T>>.PooledObject Get(out List<T> value) => s_Pool.Get(out value);
        public static void Release(List<T> toRelease) => s_Pool.Release(toRelease);
    }
}