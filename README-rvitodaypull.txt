updated sql for ravi trial grouping

SELECT * , group_concat( ind SEPARATOR ';' ) AS allinds
FROM rvi_today
WHERE (all_facet_date >= '2011-01-01')
AND (
drug NOT REGEXP 'unconfirmed'
)
AND all_facet_date IS NOT NULL
GROUP BY drug, all_facet_date
ORDER BY all_facet_date ASC

Fields we use

$pvrow->{relay_id} = $hp->{ravikey};
		$pvrow->{date} = $hp->{all_facet_date};
		$pvrow->{relay_drug} = $hp->{drug};
		$pvrow->{relay_ind} = $hp->{ind};
		$pvrow->{relay_company} = $hp->{company};
		$pvrow->{relay_toplevelind} = join("|",keys %allparents);
		$pvrow->{relay_phase} = $hp->{devdrindphase};
		
So alter above to

SELECT ravikey, all_facet_date,drug,ind,company,devdrindphase, group_concat( ind SEPARATOR ';' ) AS allinds
FROM rvi_today
WHERE (all_facet_date >= '2011-01-01')
AND (
drug NOT REGEXP 'unconfirmed'
)
AND (
devdrindphase REGEXP 'phase'
)
AND (
company NOT REGEXP 'multiple|unconfirmed'
)
AND all_facet_date IS NOT NULL
GROUP BY drug, all_facet_date
ORDER BY all_facet_date ASC

4389 trials