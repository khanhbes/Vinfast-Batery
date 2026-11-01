export interface PromptLayer {
  layerIndex: 0 | 1 | 2 | 3 | 4 | 5;
  id: 'core' | 'persona' | 'knowledge' | 'context' | 'memory' | 'override';
  nameVi: string;
  locked: boolean;
  requiresTwoPersonApproval: boolean;
  tokenBudget: number;
  templateText: string;
  variables: string[];
}

export interface PersonaSetting {
  presetId: 'companion' | 'concise' | 'expert' | 'concierge';
  nameVi: string;
  descriptionVi: string;
  botName: string;
  defaultSelfPronoun: string;
  defaultUserPronoun: string;
  honorificRespectUserMemory: boolean;
  sliders: {
    brevity: number;
    warmth: number;
    technicalDepth: number;
    proactivity: number;
  };
  drivingModeMaxSentences: number;
  promptInstructionVi: string;
}

export interface GuardrailPolicy {
  blockPromptInjection: boolean;
  maskPiiInLogs: boolean;
  requireDisambiguationOnMultiVehicle: boolean;
  enforceQa137Format: boolean;
  forbiddenTopics: string[];
  emergencyKeywords: string[];
  emergencyResponseVi: string;
  blockedInputPatterns: string[];
}

export interface ToolDefinition {
  name: string;
  labelVi: string;
  executionSide: 'server' | 'client_action';
  riskLevel: 1 | 2 | 3;
  enabled: boolean;
  allowedTiers: ('free' | 'pro' | 'ultra' | 'fleet')[];
  rateLimitPerMinute: number;
  timeoutMs: number;
  requireTargetConfirmation: boolean;
  disabledInSafeMode: boolean;
}

export interface PinovaConfigVersion {
  versionId: string;
  status: 'draft' | 'published' | 'canary' | 'archived';
  basedOnVersionId: string | null;
  releaseNote: string;
  createdBy: string;
  approvedBy: string | null;
  createdAt: string;
  publishedAt: string | null;
  modelConfig: {
    provider: 'gemini_apim_relay' | 'openai_compatible';
    primaryModel: string;
    fallbackModel: string;
    temperature: number;
    topP: number;
    maxOutputTokens: number;
    timeoutMs: number;
  };
  layers: PromptLayer[];
  persona: PersonaSetting;
  guardrails: GuardrailPolicy;
  tools: ToolDefinition[];
}

export interface MemoryItem {
  id: string;
  uid: string;
  scope: 'user' | 'vehicle' | 'org';
  vehicleId?: string | null;
  category: 'profile' | 'vehicle_context' | 'habit' | 'preference' | 'location_safe' | 'other';
  categoryLabelVi: string;
  text: string;
  maskedText: string;
  confidence: number;
  sensitivity: 'normal' | 'sensitive';
  status: 'active' | 'pending_confirmation' | 'expired' | 'deleted_by_user';
  source: 'user_explicit' | 'model_inferred' | 'admin_configured' | 'telemetry_learned';
  createdAt: string;
  updatedAt?: string;
  expiresAt: string | null;
}

export interface KnowledgeSource {
  id: string;
  title: string;
  category: string;
  categoryLabelVi: string;
  keywords: string[];
  body: string;
  priority: number;
  enabled: boolean;
  effectiveFrom: string;
  effectiveUntil: string | null;
  updatedAt?: string;
}

export interface EvalCase {
  id: string;
  title: string;
  suite: string;
  suiteLabelVi: string;
  mockContext: Record<string, unknown>;
  userMessage: string;
  expectedCriteria: {
    mustCallTools?: string[];
    mustNotCallTools?: string[];
    mustContainPhrases?: string[];
    mustNotContainPhrases?: string[];
    expectDisambiguation?: boolean;
    expectEmergencyBypass?: boolean;
  };
}

export interface EvalRunResult {
  caseId: string;
  title: string;
  suite: string;
  suiteLabelVi: string;
  passed: boolean;
  reply: string;
  calledTools: string[];
  failureReason?: string;
  latencyMs: number;
}

export interface EvalRun {
  runId: string;
  versionId: string;
  executedAt: string;
  executedBy: string;
  totalCases: number;
  passedCases: number;
  safetyScorePct: number;
  qualityScorePct: number;
  avgLatencyMs: number;
  results: EvalRunResult[];
}

export interface ReleasePlan {
  releaseId: string;
  versionId: string;
  previousVersionId: string;
  stage: 'internal' | 'canary_5' | 'canary_25' | 'full_100' | 'rolled_back';
  rolloutPercent: number;
  evalRunId: string;
  autoRollbackOnErrorRatePct: number;
  updatedAt: string;
  updatedBy: string;
  rollbackReason?: string;
}

export interface KillSwitchState {
  mode: 'normal' | 'safe_mode' | 'disabled';
  reason: string;
  fallbackMessageVi: string;
  updatedBy: string;
  updatedAt: string;
}

