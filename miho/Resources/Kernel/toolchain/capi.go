package main

import "C"

import (
	"encoding/json"
	"sync"
	"unsafe"

	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	gate sync.RWMutex
	core *coreCtx
)

type coreCtx struct {
	initialized bool
	running     bool
	homeDir     string
	configFile  string

	trafficCb C.MihomoTrafficCallback
	trafficCtx unsafe.Pointer

	memoryCb C.MihomoMemoryCallback
	memoryCtx unsafe.Pointer

	logCb C.MihomoLogCallback
	logCtx unsafe.Pointer

	stateChangeCb C.MihomoStateChangeCallback
	stateChangeCtx unsafe.Pointer
}

func seize(write, ensure bool) (*coreCtx, func(), bool) {
	if write {
		gate.Lock()
	} else {
		gate.RLock()
	}
	released := false
	rel := func() {
		if released {
			return
		}
		released = true
		if write {
			gate.Unlock()
		} else {
			gate.RUnlock()
		}
	}
	if ensure && core == nil {
		core = &coreCtx{}
	}
	if core == nil {
		rel()
		return nil, func() {}, false
	}
	return core, rel, true
}

func main() {}
