// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.

import { Context } from "mocha";
import * as dotenv from "dotenv";

import {
  env,
  Recorder,
  record,
  RecorderEnvironmentSetup,
  isPlaybackMode
} from "@azure/test-utils-recorder";
import {
  DefaultHttpClient,
  HttpClient,
  HttpOperationResponse,
  isNode,
  TokenCredential,
  WebResourceLike
} from "@azure/core-http";
import { PhoneNumbersClient, PhoneNumbersClientOptions } from "../../../src";
import { parseConnectionString } from "@azure/communication-common";
import { DefaultAzureCredential } from "@azure/identity";

if (isNode) {
  dotenv.config();
}

export interface RecordedClient<T> {
  client: T;
  recorder: Recorder;
}

const replaceableVariables: { [k: string]: string } = {
  AZURE_COMMUNICATION_LIVETEST_CONNECTION_STRING: "endpoint=https://endpoint/;accesskey=banana",
  INCLUDE_PHONENUMBER_LIVE_TESTS: "false",
  COMMUNICATION_ENDPOINT: "https://endpoint/",
  AZURE_CLIENT_ID: "SomeClientId",
  AZURE_CLIENT_SECRET: "SomeClientSecret",
  AZURE_TENANT_ID: "SomeTenantId",
  AZURE_PHONE_NUMBER: "+14155550100"
};

export const environmentSetup: RecorderEnvironmentSetup = {
  replaceableVariables,
  customizationsOnRecordings: [
    (recording: string): string => recording.replace(/(https:\/\/)([^/'",}]*)/, "$1endpoint"),
    (recording: string): string => recording.replace(/\d{1}\d{3}\d{3}\d{4}/g, "14155550100"),
    (recording: string): string =>
      recording.replace(/[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}/gi, "sanitized")
  ],
  queryParametersToSkip: []
};

export function createRecordedClient(context: Context): RecordedClient<PhoneNumbersClient> {
  const recorder = record(context, environmentSetup);

  // casting is a workaround to enable min-max testing
  return {
    client: new PhoneNumbersClient(env.AZURE_COMMUNICATION_LIVETEST_CONNECTION_STRING, {
      httpClient: createTestHttpClient()
    } as PhoneNumbersClientOptions),
    recorder
  };
}

export const canCreateRecordedClientWithToken = (): boolean => {
  try {
    new DefaultAzureCredential();
    return true;
  } catch {
    return false;
  }
};

export function createRecordedClientWithToken(
  context: Context
): RecordedClient<PhoneNumbersClient> | undefined {
  const recorder = record(context, environmentSetup);
  let credential: TokenCredential;
  const endpoint = parseConnectionString(env.AZURE_COMMUNICATION_LIVETEST_CONNECTION_STRING)
    .endpoint;
  if (isPlaybackMode()) {
    credential = {
      getToken: async (_scopes) => {
        return { token: "testToken", expiresOnTimestamp: 11111 };
      }
    };

    // casting is a workaround to enable min-max testing
    return {
      client: new PhoneNumbersClient(endpoint, credential, {
        httpClient: createTestHttpClient()
      } as PhoneNumbersClientOptions),
      recorder
    };
  }

  try {
    credential = new DefaultAzureCredential();
  } catch {
    return undefined;
  }

  // casting is a workaround to enable min-max testing
  return {
    client: new PhoneNumbersClient(endpoint, credential, {
      httpClient: createTestHttpClient()
    } as PhoneNumbersClientOptions),
    recorder
  };
}

export const testPollerOptions = {
  pollInterval: isPlaybackMode() ? 0 : undefined
};

function createTestHttpClient(): HttpClient {
  const customHttpClient = new DefaultHttpClient();

  const originalSendRequest = customHttpClient.sendRequest;
  customHttpClient.sendRequest = async function(
    httpRequest: WebResourceLike
  ): Promise<HttpOperationResponse> {
    const requestResponse = await originalSendRequest.apply(this, [httpRequest]);

    if (requestResponse.status < 200 || requestResponse.status > 299) {
      console.log(`MS-CV header for failed request: ${requestResponse.headers.get("ms-cv")}`);
    }

    return requestResponse;
  };

  return customHttpClient;
}
