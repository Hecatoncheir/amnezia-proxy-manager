// Каркас диагностики. Запуск туннеля ещё не реализован.
package main

import (
	"encoding/json"
	"fmt"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/upstream"
	"os"
)

func main() {
	if len(os.Args) != 2 || os.Args[1] != "--capabilities" {
		fmt.Fprintln(os.Stderr, "Каркас движка: используйте --capabilities; запуск туннеля недоступен")
		os.Exit(2)
	}
	if err := json.NewEncoder(os.Stdout).Encode(map[string]any{
		"protocolVersion": 1, "status": "scaffold", "canStart": false,
		"backend": "synacker/amnezia-proxy", "upstreamRevision": upstream.Revision,
	}); err != nil {
		os.Exit(1)
	}
}
