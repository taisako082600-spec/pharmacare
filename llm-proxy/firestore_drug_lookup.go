package main

import "time"

// firestoreDrugLookup は DrugMasterLookup インターフェース(drug_matching.go)の
// Firestore実装。drug_name_aliases / drug_master / unmatched_drug_names を操作する。
type firestoreDrugLookup struct {
	client *FirestoreClient
}

func (f *firestoreDrugLookup) LookupAlias(normalized string) (string, bool, error) {
	fields, found, err := f.client.GetDocument("drug_name_aliases", normalized)
	if err != nil || !found {
		return "", false, err
	}
	generic, _ := fields["genericName"].(string)
	return generic, generic != "", nil
}

func (f *firestoreDrugLookup) LookupMaster(normalized string) (string, bool, error) {
	fields, found, err := f.client.GetDocument("drug_master", normalized)
	if err != nil || !found {
		return "", false, err
	}
	generic, _ := fields["genericName"].(string)
	return generic, generic != "", nil
}

func (f *firestoreDrugLookup) QueueUnmatched(rawInput, normalized string) error {
	// 同じ正規化文字列が既にキューにあれば重複登録しない
	existing, found, err := f.client.GetDocument("unmatched_drug_names", normalized)
	if err == nil && found {
		if status, _ := existing["status"].(string); status == "pending" {
			return nil
		}
	}

	return f.client.SetDocument("unmatched_drug_names", normalized, map[string]interface{}{
		"rawInput":        rawInput,
		"normalizedInput": normalized,
		"status":          "pending",
		"createdAt":       time.Now(),
	})
}

// fetchKnowledgeEntry は drug_knowledge_base/{一般名} を取得し、Go の構造体に変換する。
func fetchKnowledgeEntry(client *FirestoreClient, genericName string) (DrugKnowledgeEntry, bool, error) {
	fields, found, err := client.GetDocument("drug_knowledge_base", genericName)
	if err != nil || !found {
		return DrugKnowledgeEntry{}, false, err
	}

	status, _ := fields["status"].(string)
	entry := DrugKnowledgeEntry{
		GenericName: genericName,
		Status:      status,
		Sections:    map[string]DrugKnowledgeSection{},
	}

	sectionsRaw, ok := fields["sections"].(map[string]interface{})
	if !ok {
		return entry, true, nil
	}
	for category, v := range sectionsRaw {
		m, ok := v.(map[string]interface{})
		if !ok {
			continue
		}
		sectionNumber, _ := m["sectionNumber"].(string)
		sectionTitle, _ := m["sectionTitle"].(string)
		text, _ := m["text"].(string)
		entry.Sections[category] = DrugKnowledgeSection{
			SectionNumber: sectionNumber,
			SectionTitle:  sectionTitle,
			Text:          text,
		}
	}
	return entry, true, nil
}
