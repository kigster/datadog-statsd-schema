# Future Direction

## Small Features & Improvements

 * Validation mode: raise or log the error, but send the non-compliant metric anyway (good for migrations from raw statsd to `emitter`)

## Large Features / Stories

<dt>"The Service Registry" gem — <code>datadog-statsd-registry</code></dt>
<dd>The gem would use <code>self.inherited</code> hook to auto-register each emitter and each schema in the global registry, to be recallable and searchable anywhere in the application code. This would encourage possible pre-declaration of most key emitters in a single initializer file, while still allowing ad-hoc creation, that does not get attached to the registry and will be garbage collected. Emitters are largely just a pre-determined combination of tags and a metric prefix, with a schema of allowable metrics and tags. It could be beneficial to reuse say <code>@email_stats_emitter</code> among multiple mailers in the system, but how to you get then to share an instance without some sort of a registry or IoC? Have schema and emmitter instances register by name in the global application space.<br/><br />

Example:
<pre>
emitter = Datadog::Statsd.registry[:email_emitter]
emitter.increment('total')
</pre>
</dd>

<dt>Ensure Thread Safety for Emitter</dt>
<dd>If emitters are to be shared, they necessarily must be thread safe, as should be the underlying <code>Datadog::Statsd</code></dd>

### Multi-Gem Design

 * Split `Datadog::Statsd::Emitter` class into its own gem, eg `datadog-statsd-emitter` without the schema. Allow emitter to receive a validator proc for extensions.
 * Make this schema gem a validation extension to the emitter gem.

Allow in the end a mix-match of:
 * `datadog-statsd-emitter`
 * `datadog-statsd-registry`
 * `datadog-statsd-schema`


