/*
Copyright 2016 The Kubernetes Authors All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package systemlogmonitor

import (
	"fmt"
	"reflect"
	"runtime"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	watchertest "k8s.io/node-problem-detector/pkg/systemlogmonitor/logwatchers/testing"
	logtypes "k8s.io/node-problem-detector/pkg/systemlogmonitor/types"
	"k8s.io/node-problem-detector/pkg/types"
)

const (
	testSource     = "TestSource"
	testConditionA = "TestConditionA"
	testConditionB = "TestConditionB"
)

func TestGenerateStatus(t *testing.T) {
	initConditions := []types.Condition{
		{
			Type:       testConditionA,
			Status:     true,
			Transition: time.Unix(500, 500),
			Reason:     "initial reason",
		},
		{
			Type:       testConditionB,
			Status:     false,
			Transition: time.Unix(500, 500),
		},
	}
	logs := []*logtypes.Log{
		{
			Timestamp: time.Unix(1000, 1000),
			Message:   "test message 1",
		},
		{
			Timestamp: time.Unix(2000, 2000),
			Message:   "test message 2",
		},
	}
	for c, test := range []struct {
		rule     logtypes.Rule
		expected types.Status
	}{
		// Do not need Pattern because we don't do pattern match in this test
		{
			rule: logtypes.Rule{
				Type:      types.Perm,
				Condition: testConditionA,
				Reason:    "test reason",
			},
			expected: types.Status{
				Source: testSource,
				Conditions: []types.Condition{
					{
						Type:       testConditionA,
						Status:     true,
						Transition: time.Unix(1000, 1000),
						Reason:     "test reason",
						Message:    "test message 1\ntest message 2",
					},
					initConditions[1],
				},
			},
		},
		// Should not update transition time when status and reason are not changed.
		{
			rule: logtypes.Rule{
				Type:      types.Perm,
				Condition: testConditionA,
				Reason:    "initial reason",
			},
			expected: types.Status{
				Source: testSource,
				Conditions: []types.Condition{
					{
						Type:       testConditionA,
						Status:     true,
						Transition: time.Unix(500, 500),
						Reason:     "initial reason",
					},
					initConditions[1],
				},
			},
		},
		{
			rule: logtypes.Rule{
				Type:   types.Temp,
				Reason: "test reason",
			},
			expected: types.Status{
				Source: testSource,
				Events: []types.Event{{
					Severity:  types.Warn,
					Timestamp: time.Unix(1000, 1000),
					Reason:    "test reason",
					Message:   "test message 1\ntest message 2",
				}},
				Conditions: initConditions,
			},
		},
	} {
		l := &logMonitor{
			config: MonitorConfig{
				Source: testSource,
			},
			// Copy the init conditions to make sure it's not changed
			// during the test.
			conditions: append([]types.Condition{}, initConditions...),
		}
		got := l.generateStatus(logs, test.rule)
		if !reflect.DeepEqual(&test.expected, got) {
			t.Errorf("case %d: expected status %+v, got %+v", c+1, test.expected, got)
		}
	}
}

func TestGoroutineLeak(t *testing.T) {
	orignal := runtime.NumGoroutine()
	f := watchertest.NewFakeLogWatcher(10)
	f.InjectError(fmt.Errorf("unexpected error"))
	l := &logMonitor{watcher: f}
	_, err := l.Start()
	assert.Error(t, err)
	assert.Equal(t, orignal, runtime.NumGoroutine())
}
