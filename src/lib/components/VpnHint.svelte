<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
<script lang="ts">
  /*
   * The VPN recommendation for Direct mode: one sentence, a link to the blog post, and a button
   * that hides it for good (see `src/lib/vpnHint.ts`); it saves that itself and shows why if it
   * could not. `onClose`, if given, adds a button that only hides it for now.
   */
  import { errorMessage } from '../ipc';
  import { VPN_HINT, dismissVpnHint, openVpnPost } from '../vpnHint';

  interface Props {
    /** Called once the dismissal is saved. */
    onDismissed?: () => void;
    /** Hides the note until it is shown again. */
    onClose?: () => void;
  }

  let { onDismissed, onClose }: Props = $props();

  let saving = $state(false);
  let error = $state<string | null>(null);

  function dismiss(): void {
    saving = true;
    error = null;
    dismissVpnHint()
      .then(() => {
        onDismissed?.();
      })
      .catch((reason: unknown) => {
        error = `The setting could not be saved: ${errorMessage(reason)}`;
      })
      .finally(() => {
        saving = false;
      });
  }
</script>

<div class="hint" role="note">
  <p>{VPN_HINT}</p>
  <div class="actions">
    <button type="button" class="link" onclick={openVpnPost}>Why use a VPN?</button>
    <button type="button" class="quiet" disabled={saving} onclick={dismiss}>Don't show again</button
    >
    {#if onClose}
      <button type="button" class="quiet" onclick={onClose}>Close</button>
    {/if}
  </div>
  {#if error}
    <p class="error" role="alert">{error}</p>
  {/if}
</div>

<style>
  .hint {
    padding: 0.75rem 1rem;
    border-radius: 0.6rem;
    background: rgb(242 180 90 / 8%);
    color: var(--text);
    font-size: 0.85rem;
    line-height: 1.45;
  }

  p {
    margin: 0;
  }

  .error {
    margin-top: 0.4rem;
    color: #e8907a;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem 1rem;
    margin-top: 0.5rem;
  }

  button {
    padding: 0;
    border: none;
    background: none;
    font: inherit;
    cursor: pointer;
  }

  .link {
    color: var(--accent);
    font-weight: 500;
  }

  .quiet {
    color: var(--text-muted);
  }

  .quiet:hover {
    color: var(--text);
  }

  button:focus-visible {
    border-radius: 0.2rem;
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }
</style>
